"""
Lambda: Inbound decryption with AWS KMS (asymmetric)
Trigger: S3 ObjectCreated on prefix inbound/*.enc
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

        # Skip placeholders and already-decrypted files
        if key.endswith(".keep") or key.endswith("_decrypted.txt"):
            logger.info(f"Skipping: {key}")
            continue

        logger.info(f"[INBOUND] Processing (KMS decrypt): s3://{bucket}/{key}")

        try:
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            ciphertext = obj["Body"].read()

            decrypt_resp = kms_client.decrypt(
                KeyId=kms_key_id,
                CiphertextBlob=ciphertext,
                EncryptionAlgorithm="RSAES_OAEP_SHA_256",
            )
            plaintext_bytes = decrypt_resp["Plaintext"]
            plaintext = plaintext_bytes.decode("utf-8")

            logger.info(f"[INBOUND] Decryption SUCCESS for: {key}")

            if "TRANSFER_FAMILY_PGP_OK" in plaintext:
                logger.info("[INBOUND] POC VALIDATION PASSED checksum_word found")
                poc_validation = "PASSED"
            else:
                logger.warning(
                    "[INBOUND] checksum_word not found — may not be the test payload"
                )
                poc_validation = "UNKNOWN"

            decrypted_key = key.replace(".enc", "_decrypted.txt")
            s3_client.put_object(
                Bucket=bucket,
                Key=decrypted_key,
                Body=plaintext_bytes,
                Metadata={
                    "original-file": key,
                    "decryption-status": "success",
                    "poc-validation": poc_validation,
                },
            )

            logger.info(
                f"[INBOUND] Decrypted file saved to: s3://{bucket}/{decrypted_key}"
            )
            results.append(
                {"file": key, "status": "decrypted", "output": decrypted_key}
            )

        except Exception as e:
            logger.error(f"[INBOUND] FAILED for {key}: {str(e)}", exc_info=True)
            raise

    return {
        "statusCode": 200,
        "body": json.dumps(
            {"message": "Inbound KMS decryption completed", "results": results}
        ),
    }

