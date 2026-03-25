import boto3
import json
import urllib.parse
import logging
import os
import base64


logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get("BUCKET_NAME")


def _derive_decrypted_filename(encrypted_filename: str) -> str:
    """
    pain_0001.txt.enc -> pain_0001_decrypted.txt
    Si no termina con .txt, usa el sufijo _decrypted.txt como fallback.
    """
    if encrypted_filename.endswith(".enc"):
        original = encrypted_filename[: -len(".enc")]
    else:
        original = encrypted_filename

    if original.endswith(".txt"):
        return original[: -len(".txt")] + "_decrypted.txt"
    return original + "_decrypted.txt"


def _require_env():
    if not BUCKET_NAME:
        raise ValueError("Missing env var BUCKET_NAME")


def lambda_handler(event, context):
    """
    Fase 2 (POC simplificado):
    - Entrada: inbound/* con sufijo .enc (pain_0001.txt.enc)
    - "Desencripta" Base64
    - Guarda texto plano en inbound/<pain_0001_decrypted.txt>
    - Crea pain_0002 en texto y lo codifica en Base64 (.enc simulado)
    - Guarda en outbound/pain_0002.enc (lo transfiere outbound_sender)
    """
    _require_env()

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        logger.info(f"Procesando (Fase 2): s3://{bucket}/{key}")

        # Solo procesar archivos en inbound/ con sufijo .enc
        if not key.startswith("inbound/") or not key.endswith(".enc"):
            logger.info(f"Ignorando archivo (no inbound/ o no .enc): {key}")
            continue

        encrypted_filename = key.split("/")[-1]
        decrypted_filename = _derive_decrypted_filename(encrypted_filename)
        folder = key.rsplit("/", 1)[0]  # conserva la carpeta dentro de inbound/

        response = s3.get_object(Bucket=bucket, Key=key)
        encrypted_content = response["Body"].read().strip()

        # "Desencriptar" Base64 (strip por CRLF/espacios al subir el .enc)
        content_bytes = base64.b64decode(encrypted_content, validate=False)
        content = content_bytes.decode("utf-8")

        logger.info(f"Contenido desencriptado (preview): {content[:120]}")

        # 1) Guardar pain_0001_decrypted.txt en inbound/
        decrypted_key = f"{folder}/{decrypted_filename}"
        s3.put_object(
            Bucket=bucket,
            Key=decrypted_key,
            Body=content_bytes,
            ContentType="text/plain",
        )
        logger.info(f"Archivo desencriptado guardado en: s3://{bucket}/{decrypted_key}")

        # 2) Crear pain_0002 y "encriptarlo" en Base64
        new_content = content + "\n[OUTBOUND - procesado por Lambda Fase 2]"
        plaintext_bytes = new_content.encode("utf-8")
        cipher_bytes = base64.b64encode(plaintext_bytes)

        outbound_key = "outbound/pain_0002.enc"
        s3.put_object(
            Bucket=bucket,
            Key=outbound_key,
            Body=cipher_bytes,
            ContentType="text/plain",
        )
        logger.info(f"Archivo en Base64 guardado en: s3://{bucket}/{outbound_key}")

    return {"statusCode": 200, "body": json.dumps("Fase 2 inbound OK")}

