#!/bin/bash
# Prueba manual del flujo Fase 1
# Requisitos: sftp instalado, claves generadas, infra desplegada

set -e

# --- COMPLETAR ESTOS VALORES DESPUES DE DESPLEGAR CON TERRAFORM ---
SFTP_SERVER_ENDPOINT=$(terraform -chdir=../terraform output -raw transfer_server_endpoint)
SFTP_USERNAME="sftpuser"
PRIVATE_KEY_PATH="./keys/sftp_user_key"
BUCKET_NAME=$(terraform -chdir=../terraform output -raw s3_bucket_name)
# ------------------------------------------------------------------

TEST_FILE="pain_0001.txt"
echo "Archivo de prueba Fase 1 - $(date)" > "/tmp/$TEST_FILE"
echo "Este es un archivo de texto plano para el POC SFTP." >> "/tmp/$TEST_FILE"

echo "📤 Subiendo $TEST_FILE al servidor SFTP..."
sftp -i "$PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  "${SFTP_USERNAME}@${SFTP_SERVER_ENDPOINT}" <<EOF
put /tmp/$TEST_FILE
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
echo "📥 pain_0002.enc en /outbound (Base64); texto decodificado:"
if aws s3 cp "s3://${BUCKET_NAME}/outbound/pain_0002.enc" /tmp/pain_0002.enc -q 2>/dev/null; then
  base64 --decode /tmp/pain_0002.enc > /tmp/pain_0002_decrypted.txt
  cat /tmp/pain_0002_decrypted.txt
else
  echo "(archivo aun no disponible)"
fi

echo ""
echo "✅ Prueba Fase 1 completada. Verificar en sftpcloud.io que llegó pain_0002.enc"

