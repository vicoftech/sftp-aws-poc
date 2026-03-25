import boto3
import json
import urllib.parse
import logging
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')


def lambda_handler(event, context):
    """
    Fase 1: Lee pain_0001.txt de /inbound, agrega texto outbound,
    codifica en Base64 y guarda pain_0002.enc en /outbound.
    """
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])

        logger.info(f"Procesando archivo: s3://{bucket}/{key}")

        # Solo procesar archivos en inbound/
        if not key.startswith('inbound/'):
            logger.info(f"Ignorando archivo fuera de inbound/: {key}")
            continue

        # Fase 2: los archivos cifrados se suben como *.enc (pain_0001.txt.enc).
        # Para mantener Fase 1 estable (sin intentar decodear binario), los ignoramos.
        if key.endswith('.enc'):
            logger.info(f"Ignorando archivo cifrado (.enc) en Fase 1: {key}")
            continue

        # Salida intermedia de Fase 2 (evita pisar outbound/pain_0002.enc de Fase 2).
        if '_decrypted.txt' in key.split('/')[-1]:
            logger.info(f"Ignorando archivo intermedio Fase 2 en Fase 1: {key}")
            continue

        # Leer el archivo
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')

        logger.info(f"Contenido original: {content}")

        # Modificar: agregar texto "outbound"
        new_content = content + "\n[OUTBOUND - procesado por Lambda Fase 1]"

        outbound_key = "outbound/pain_0002.enc"
        cipher_bytes = base64.b64encode(new_content.encode("utf-8"))

        s3.put_object(
            Bucket=bucket,
            Key=outbound_key,
            Body=cipher_bytes,
            ContentType="text/plain",
        )

        logger.info(f"Archivo guardado en: s3://{bucket}/{outbound_key}")

    return {
        'statusCode': 200,
        'body': json.dumps('Procesamiento Fase 1 completado')
    }

