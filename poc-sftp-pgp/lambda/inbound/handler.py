"""
Lambda: Inbound PGP Decryption
Trigger: S3 ObjectCreated on prefix inbound/*.pgp
Source: https://github.com/aws-ia/terraform-aws-transfer-family
"""
import boto3
import pgpy
import os
import json
import logging
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

    # Skip placeholders and already-decrypted files
    if key.endswith(".keep") or "_decrypted" in key:
      logger.info(f"Skipping: {key}")
      continue

    logger.info(f"[INBOUND] Processing: s3://{bucket}/{key}")

    try:
      # 1. Load internal private key from Secrets Manager
      private_key_pem = get_secret(os.environ["INTERNAL_PRIVATE_KEY_SECRET_ARN"])
      private_key, _ = pgpy.PGPKey.from_blob(private_key_pem)

      # 2. Download encrypted file from S3
      obj = s3_client.get_object(Bucket=bucket, Key=key)
      encrypted_data = obj["Body"].read().decode("utf-8")

      # 3. Load encrypted message
      pgp_message = pgpy.PGPMessage.from_blob(encrypted_data)

      # 4. Decrypt
      passphrase = os.environ.get("PGP_PASSPHRASE", "")
      if passphrase:
        with private_key.unlock(passphrase):
          decrypted = private_key.decrypt(pgp_message)
      else:
        decrypted = private_key.decrypt(pgp_message)

      decrypted_content = decrypted.message
      if isinstance(decrypted_content, (bytes, bytearray)):
        decrypted_content = decrypted_content.decode("utf-8")

      logger.info(f"[INBOUND] Decryption SUCCESS for: {key}")

      # 5. POC Validation
      if "TRANSFER_FAMILY_PGP_OK" in decrypted_content:
        logger.info("[INBOUND] POC VALIDATION PASSED \u2713 checksum_word found")
      else:
        logger.warning(
          "[INBOUND] checksum_word not found — may not be the test payload"
        )

      # 6. Upload decrypted file to S3 inbound/
      decrypted_key = (
        key.replace(".pgp", "_decrypted.txt").replace(".gpg", "_decrypted.txt")
      )
      s3_client.put_object(
        Bucket=bucket,
        Key=decrypted_key,
        Body=decrypted_content.encode("utf-8"),
        Metadata={
          "original-file": key,
          "decryption-status": "success",
          "poc-validation": "PASSED"
          if "TRANSFER_FAMILY_PGP_OK" in decrypted_content
          else "UNKNOWN",
        },
      )

      logger.info(
        f"[INBOUND] Decrypted file saved to: s3://{bucket}/{decrypted_key}"
      )
      results.append({"file": key, "status": "decrypted", "output": decrypted_key})

    except Exception as e:
      logger.error(f"[INBOUND] FAILED for {key}: {str(e)}", exc_info=True)
      raise

  return {
    "statusCode": 200,
    "body": json.dumps(
      {"message": "Inbound decryption completed", "results": results}
    ),
  }

