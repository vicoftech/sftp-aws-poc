# Guía de Conexión — Cliente SFTP Externo

## Datos de Conexión al Transfer Family Server

| Parámetro   | Valor                                              |
|-------------|----------------------------------------------------|
| Host        | `s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com` |
| Puerto      | `22`                                               |
| Usuario     | `sftpuser`                                         |
| Autenticación | Clave privada SSH (`keys/sftp_user_key`)         |
| Directorio  | `/` (raíz = `/inbound/` en el bucket S3)           |

> Endpoint (real): `s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com`

## Cómo Conectar con FileZilla

1. Abrir FileZilla → **Archivo > Gestor de Sitios > Nuevo Sitio**
2. Protocolo: `SFTP - SSH File Transfer Protocol`
3. Servidor: `s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com`
4. Puerto: `22`
5. Modo de acceso: `Archivo de claves`
6. Usuario: `sftpuser`
7. Archivo de clave: seleccionar `keys/sftp_user_key`
8. Clic en **Conectar**

## Cómo Conectar con WinSCP

1. Nueva sesión → Protocolo: SFTP
2. Host: `s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com`
3. Puerto: `22`
4. Usuario: `sftpuser`
5. **Avanzado > SSH > Autenticación > Archivo de clave privada**: seleccionar `keys/sftp_user_key`
6. Conectar

> WinSCP puede pedir convertir la clave a formato PPK. Aceptar la conversión.

## Cómo Conectar con CLI (sftp)

```bash
sftp -i keys/sftp_user_key -o StrictHostKeyChecking=no \
  sftpuser@s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com
```

## Flujo de Prueba Manual

### Fase 1

```bash
# Crear archivo de prueba
echo "Archivo de prueba Fase 1" > pain_0001.txt

# Conectar y subir
sftp -i keys/sftp_user_key sftpuser@s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com
sftp> put pain_0001.txt
sftp> bye

# Verificar en S3 (esperar ~15 segundos)
aws s3 ls s3://workium-sftp-poc-sftp-poc-dev/inbound/
aws s3 ls s3://workium-sftp-poc-sftp-poc-dev/outbound/
```

### Fase 2

```bash
# Encriptar archivo antes de subir
gpg --encrypt --recipient <pgp_recipient_id> pain_0001.txt
# Genera pain_0001.txt.gpg

# Conectar y subir el archivo encriptado
sftp -i keys/sftp_user_key sftpuser@s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com
sftp> put pain_0001.txt.gpg
sftp> bye
```

## Servidor SFTP Externo (sftpcloud.io)

| Parámetro | Valor                              |
|-----------|------------------------------------|
| Host      | `us-east-1.sftpcloud.io`           |
| Puerto    | `22`                               |
| Usuario   | `ca43baf534464d49a233683bd17fff1f` |
| Password  | `(leer desde Secrets Manager: workium-sftp-poc/sftp-connector/credentials)` |

Este servidor es el **destino** de la transferencia. Los archivos enviados
por Lambda via Transfer Connector aparecerán en la carpeta `/upload/`.

---

## Orden de Ejecución para Cursor

### Paso 1 — Generar estructura del proyecto

```
Crear la estructura de carpetas completa del proyecto sftp-poc/ 
tal como está definida en este prompt.
```

### Paso 2 — Terraform Fase 1

```
Implementar todos los archivos .tf de Fase 1:
main.tf, variables.tf, outputs.tf, iam.tf, s3.tf, 
transfer_server.tf, transfer_connector.tf, lambda_inbound.tf
```

### Paso 3 — Lambdas Fase 1

```
Implementar:
- lambdas/inbound/handler_phase1.py
- lambdas/outbound/handler_outbound.py
```

### Paso 4 — Scripts y README

```
Implementar:
- scripts/generate_sftp_keys.sh
- scripts/test_phase1.sh
- README.md
- README_CONEXION.md
```

### Paso 5 — Validar y desplegar

```
1. Ejecutar: cd scripts && ./generate_sftp_keys.sh
2. Copiar la clave pública en terraform/variables.tf
3. Ejecutar: cd terraform && terraform init && terraform plan && terraform apply
4. Anotar los outputs: endpoint del servidor y bucket name
5. Actualizar README_CONEXION.md con los valores reales
6. Ejecutar: ./scripts/test_phase1.sh
```

### Paso 6 — ⏸ STOP: Validación manual Fase 1

```
Antes de continuar con Fase 2, verificar manualmente:
✅ Cliente SFTP se conecta al Transfer Family Server
✅ pain_0001.txt aparece en s3://<bucket>/inbound/
✅ pain_0002.txt aparece en s3://<bucket>/outbound/
✅ pain_0002.txt contiene el texto "[OUTBOUND - procesado por Lambda Fase 1]"
✅ pain_0002.txt llegó al servidor sftpcloud.io en /upload/
Confirmar antes de continuar con Fase 2.
```

### Paso 7 — Fase 2 (solo después de confirmar Paso 6)

```
Implementar Fase 2:
- terraform/kms.tf
- terraform/secrets.tf
- lambdas/inbound/handler_phase2.py
- lambdas/outbound/handler_phase2.py
- scripts/test_phase2.sh
Actualizar lambda_inbound.tf para soportar variable PHASE=2
```

---

## Notas Importantes

- **IAM**: El rol del conector Transfer Family necesita permisos `s3:GetObject` y `s3:PutObject` en el bucket. Sin esto, el conector falla con Access Denied.
- **IAM (Secrets Manager)**: El rol del conector también necesita permisos `secretsmanager:GetSecretValue` (y decrypt KMS si aplica) para leer `Username/Password/PrivateKey`.
- **Trusted host keys**: Solo incluir la parte `ecdsa-sha2-nistp256 AAAA...` sin el hostname al final.
- **PEM del conector**: La clave privada PEM se almacena en Secrets Manager como parte del secret del conector (campo `PrivateKey` en el JSON del secreto).
- **Evento S3 → Lambda**: Los prefijos `inbound/` y `outbound/` deben terminar con `/` en el filter.
- **Lambda Layer para GPG**: En Fase 2, si `gpg` no está disponible en el runtime de Lambda, crear un Lambda Layer con el binario GPG compilado para Amazon Linux 2.

