"""
Lambda: Outbound PGP Encryption + SFTP Send
Trigger: S3 ObjectCreated on prefix outbound/ (non-pgp files)
Source: https://github.com/aws-ia/terraform-aws-transfer-family
"""
import boto3
import pgpy
import paramiko
import os
import json
import logging
from io import BytesIO
from pgpy.constants import PubKeyAlgorithm, KeyFlags, HashAlgorithm, SymmetricKeyAlgorithm, CompressionAlgorithm

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
sm_client = boto3.client("secretsmanager")


def get_secret(secret_arn: str) -> str:
  response = sm_client.get_secret_value(SecretId=secret_arn)
  return response["SecretString"]


def handler(event, context):
  results = []

  for record in event["Records"]:
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]

    # Skip already-encrypted files, placeholders, and metadata files
    if key.endswith((".pgp", ".gpg", ".keep")) or "_encrypted" in key:
      logger.info(f"Skipping already-processed: {key}")
      continue

    logger.info(f"[OUTBOUND] Processing for encryption: s3://{bucket}/{key}")

    try:
      # 1. Load external public key from Secrets Manager
      pub_key_pem = get_secret(os.environ["EXTERNAL_PUBLIC_KEY_SECRET_ARN"])
      pub_key, _ = pgpy.PGPKey.from_blob(pub_key_pem)

      # 2. Download plaintext file from S3
      obj = s3_client.get_object(Bucket=bucket, Key=key)
      plain_data = obj["Body"].read()

      if isinstance(plain_data, (bytes, bytearray)):
        plain_text = plain_data.decode("utf-8")
      else:
        plain_text = plain_data

      # 3. Create PGP message and encrypt with external public key
      pgp_message = pgpy.PGPMessage.new(plain_text)
      encrypted_message = pub_key.encrypt(pgp_message)
      encrypted_content = str(encrypted_message).encode("utf-8")

      logger.info(f"[OUTBOUND] Encryption SUCCESS for: {key}")

      # 4. Upload encrypted file to S3 outbound/
      encrypted_key = key + ".pgp"
      s3_client.put_object(
        Bucket=bucket,
        Key=encrypted_key,
        Body=encrypted_content,
        Metadata={
          "original-file": key,
          "encryption-status": "success",
          "recipient": "external@poc.local",
        },
      )
      logger.info(f"[OUTBOUND] Encrypted file saved: s3://{bucket}/{encrypted_key}")

      # 5. Push encrypted file via SFTP (Lambda → Transfer Family endpoint)
      # Pattern: Lambda pushes to Transfer Family so external client can pull.
      # NOTE: Transfer Family is primarily inbound. For true outbound push to
      # an external SFTP server, replace sftp_host with the external server.
      # Ref: https://github.com/aws-ia/terraform-aws-transfer-family
      try:
        sftp_host = os.environ["TRANSFER_FAMILY_ENDPOINT"]
        sftp_user = os.environ["SFTP_USERNAME"]
        sftp_key_arn = os.environ["SFTP_PRIVATE_KEY_SECRET_ARN"]

        ssh_key_pem = get_secret(sftp_key_arn)
        pkey = paramiko.RSAKey.from_private_key(BytesIO(ssh_key_pem.encode()))

        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(hostname=sftp_host, username=sftp_user, pkey=pkey, timeout=30)

        sftp = ssh.open_sftp()
        remote_path = f"/{os.path.basename(encrypted_key)}"

        with sftp.open(remote_path, "wb") as remote_file:
          remote_file.write(encrypted_content)

        sftp.close()
        ssh.close()

        logger.info(
          f"[OUTBOUND] File sent via SFTP to: {sftp_host}:{remote_path}"
        )
        results.append(
          {
            "file": key,
            "status": "encrypted_and_sent",
            "output": encrypted_key,
          }
        )

      except Exception as sftp_error:
        # Non-fatal: file is already in S3, SFTP push is best-effort for POC
        logger.warning(
          f"[OUTBOUND] SFTP push failed (non-fatal for POC): {sftp_error}"
        )
        results.append(
          {
            "file": key,
            "status": "encrypted_s3_only",
            "output": encrypted_key,
          }
        )

    except Exception as e:
      logger.error(f"[OUTBOUND] FAILED for {key}: {str(e)}", exc_info=True)
      raise

  return {
    "statusCode": 200,
    "body": json.dumps(
      {"message": "Outbound encryption completed", "results": results}
    ),
  }

