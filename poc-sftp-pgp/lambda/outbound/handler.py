"""
Lambda: Outbound encryption with AWS KMS (asymmetric)
Trigger: S3 ObjectCreated on prefix outbound/ (plaintext files)
"""
import boto3
import os
import json
import logging


logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
sm_client = boto3.client("secretsmanager")
kms_client = boto3.client("kms")


def get_secret(secret_arn: str) -> str:
    response = sm_client.get_secret_value(SecretId=secret_arn)
    return response["SecretString"]


def handler(event, context):
    results = []

    kms_key_id = get_secret(os.environ["KMS_ASYM_KEY_SECRET_ARN"])

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        # Skip already-encrypted files and placeholders
        if key.endswith((".enc", ".keep")):
            logger.info(f"Skipping already-processed: {key}")
            continue

        logger.info(f"[OUTBOUND] Processing (KMS encrypt): s3://{bucket}/{key}")

        try:
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            plain_bytes = obj["Body"].read()

            encrypt_resp = kms_client.encrypt(
                KeyId=kms_key_id,
                Plaintext=plain_bytes,
                EncryptionAlgorithm="RSAES_OAEP_SHA_256",
            )
            ciphertext = encrypt_resp["CiphertextBlob"]

            encrypted_key = key + ".enc"
            s3_client.put_object(
                Bucket=bucket,
                Key=encrypted_key,
                Body=ciphertext,
                Metadata={
                    "original-file": key,
                    "encryption-status": "success",
                },
            )

            logger.info(
                f"[OUTBOUND] Encrypted file saved: s3://{bucket}/{encrypted_key}"
            )
            results.append(
                {
                    "file": key,
                    "status": "encrypted",
                    "output": encrypted_key,
                }
            )

        except Exception as e:
            logger.error(f"[OUTBOUND] FAILED for {key}: {str(e)}", exc_info=True)
            raise

    return {
        "statusCode": 200,
        "body": json.dumps(
            {"message": "Outbound KMS encryption completed", "results": results}
        ),
    }

