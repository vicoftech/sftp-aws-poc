import boto3
import json
import urllib.parse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')


def lambda_handler(event, context):
    """
    Fase 1: Lee pain_0001.txt de /inbound, agrega texto 'outbound'
    y lo guarda como pain_0002.txt en /outbound.
    """
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])

        logger.info(f"Procesando archivo: s3://{bucket}/{key}")

        # Solo procesar archivos en inbound/
        if not key.startswith('inbound/'):
            logger.info(f"Ignorando archivo fuera de inbound/: {key}")
            continue

        # Leer el archivo
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')

        logger.info(f"Contenido original: {content}")

        # Modificar: agregar texto "outbound"
        new_content = content + "\n[OUTBOUND - procesado por Lambda Fase 1]"

        # Determinar nombre de salida
        filename = key.split('/')[-1]  # pain_0001.txt
        outbound_key = f"outbound/pain_0002.txt"

        # Guardar en /outbound
        s3.put_object(
            Bucket=bucket,
            Key=outbound_key,
            Body=new_content.encode('utf-8'),
            ContentType='text/plain'
        )

        logger.info(f"Archivo guardado en: s3://{bucket}/{outbound_key}")

    return {
        'statusCode': 200,
        'body': json.dumps('Procesamiento Fase 1 completado')
    }

