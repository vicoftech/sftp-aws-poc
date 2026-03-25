import boto3
import os
import json
import urllib.parse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

transfer = boto3.client('transfer')


def lambda_handler(event, context):
    """
    Toma un objeto bajo /outbound/*.enc y lo envía al SFTP externo
    vía Transfer Family Connector (disparado por notificación S3).
    """
    connector_id = os.environ['CONNECTOR_ID']
    bucket_name = os.environ['BUCKET_NAME']
    remote_path = os.environ.get('REMOTE_PATH', '/upload')

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])

        logger.info(f"Enviando archivo: s3://{bucket}/{key}")

        # Solo procesar archivos en outbound/
        if not key.startswith('outbound/'):
            logger.info(f"Ignorando archivo fuera de outbound/: {key}")
            continue

        if not key.endswith('.enc'):
            logger.info(f"Ignorando outbound sin sufijo .enc: {key}")
            continue

        source_path = f"/{bucket}/{key}"

        # Para transferencias outbound SFTP usamos SOLO SendFilePaths
        # y RemoteDirectoryPath (no RetrieveFilePaths).
        logger.info(f"Iniciando transferencia: s3={source_path} → sftp_dir={remote_path}")

        response = transfer.start_file_transfer(
            ConnectorId=connector_id,
            SendFilePaths=[source_path],
            RemoteDirectoryPath=remote_path
        )

        logger.info(f"Transferencia iniciada. TransferId: {response.get('TransferId')}")

    return {
        'statusCode': 200,
        'body': json.dumps('Transferencia outbound iniciada')
    }

