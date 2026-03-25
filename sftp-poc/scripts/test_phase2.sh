#!/bin/bash
# Prueba manual del flujo Fase 2 (Base64, sin KMS/PGP)
# Requisitos: sftp instalado.

set -e

# --- COMPLETAR ESTOS VALORES DESPUES DE DESPLEGAR CON TERRAFORM ---
SFTP_SERVER_ENDPOINT=$(terraform -chdir=../terraform output -raw transfer_server_endpoint)
SFTP_USERNAME="sftpuser"
PRIVATE_KEY_PATH="./keys/sftp_user_key"
BUCKET_NAME=$(terraform -chdir=../terraform output -raw s3_bucket_name)
# ------------------------------------------------------------------

TEST_FILE="pain_0001.txt"
ENC_FILE="${TEST_FILE}.enc"

echo "Generando archivo de prueba Fase 2: ${TEST_FILE}..."
echo "Archivo de prueba Fase 2 - $(date)" > "/tmp/$TEST_FILE"
echo "Este es un archivo de texto plano para el POC SFTP (Fase 2 Base64)." >> "/tmp/$TEST_FILE"

echo "Codificando Base64 -> ${ENC_FILE}..."
base64 "/tmp/$TEST_FILE" > "/tmp/$ENC_FILE"

echo "📤 Subiendo ${ENC_FILE} al servidor SFTP..."
sftp -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  "${SFTP_USERNAME}@${SFTP_SERVER_ENDPOINT}" <<EOF
put /tmp/$ENC_FILE
bye
EOF

echo "✅ Archivo subido. Esperando procesamiento Lambda (15 segundos)..."
sleep 15

echo "🔍 Verificando archivos en S3..."
echo "--- /inbound ---"
aws s3 ls "s3://${BUCKET_NAME}/inbound/"
echo "--- /outbound ---"
aws s3 ls "s3://${BUCKET_NAME}/outbound/"

echo ""
echo "📥 Contenido desencriptado (pain_0001_decrypted.txt) en /inbound:"
aws s3 cp "s3://${BUCKET_NAME}/inbound/pain_0001_decrypted.txt" "/tmp/pain_0001_decrypted.txt" -q || true
echo "--- /tmp/pain_0001_decrypted.txt ---"
cat "/tmp/pain_0001_decrypted.txt" || true

echo ""
echo "📥 Descargando pain_0002.enc (Base64) y decodificando para validar..."
aws s3 cp "s3://${BUCKET_NAME}/outbound/pain_0002.enc" "/tmp/pain_0002.enc" -q

base64 --decode "/tmp/pain_0002.enc" > /tmp/pain_0002_decrypted.txt
echo "--- /tmp/pain_0002_decrypted.txt ---"
cat /tmp/pain_0002_decrypted.txt

echo ""
echo "✅ Prueba Fase 2 completada. Verificar en sftpcloud.io que llegó pain_0002.enc (Base64)."

