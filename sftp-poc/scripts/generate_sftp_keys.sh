#!/bin/bash
# Genera un par de claves SSH RSA para el usuario del Transfer Family Server
# La clave privada se usa en el cliente SFTP externo (FileZilla, WinSCP, etc.)
# La clave pública se carga en Terraform como variable sftp_user_public_key

set -e

KEY_NAME="sftp_user_key"
KEY_DIR="./keys"

mkdir -p "$KEY_DIR"

echo "Generando par de claves SSH RSA 4096..."
ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/$KEY_NAME" -N "" -C "sftp-poc-user"

echo ""
echo "✅ Claves generadas:"
echo "   Privada: $KEY_DIR/$KEY_NAME  (usar en cliente SFTP)"
echo "   Pública: $KEY_DIR/$KEY_NAME.pub"
echo ""
echo "📋 Clave pública (copiar en variables.tf → sftp_user_public_key):"
echo "---"
cat "$KEY_DIR/$KEY_NAME.pub"
echo "---"
echo ""
echo "⚠️  Guardar la clave privada de forma segura. No commitear al repositorio."
echo "   Agregar 'keys/' al .gitignore"

