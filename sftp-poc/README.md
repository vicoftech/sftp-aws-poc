# SFTP Transfer Family POC

POC de envío y recepción de archivos usando AWS Transfer Family.

## Fases

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1 | Transferencia de archivos planos | ✅ Implementar primero |
| 2 | Transferencia con encriptación KMS + PGP | ⏸ Después de validar Fase 1 |

## Arquitectura

### Fase 1
```
Cliente SFTP → Transfer Family Server → S3 /inbound/
→ Lambda inbound_processor → S3 /outbound/
→ Lambda outbound_sender → Transfer Connector → sftpcloud.io
```

### Fase 2
```
Cliente SFTP (archivo .pgp) → Transfer Family Server → S3 /inbound/
→ Lambda inbound_processor (desencripta PGP) → S3 /outbound/
→ Lambda outbound_sender (encripta PGP) → Transfer Connector → sftpcloud.io
```

## Despliegue Rápido
```bash
# 1. Generar claves SSH para el usuario SFTP
chmod +x scripts/generate_sftp_keys.sh
./scripts/generate_sftp_keys.sh

# 2. Copiar la clave pública generada en terraform/variables.tf
#    (variable: sftp_user_public_key)

# 3. Desplegar infraestructura
cd terraform
terraform init
terraform plan
terraform apply

# 4. Probar Fase 1
cd ../scripts
chmod +x test_phase1.sh
./test_phase1.sh
```

## Estructura del Proyecto

```
sftp-poc/
├── terraform/          # Infraestructura como código
├── lambdas/            # Funciones Lambda
│   ├── inbound/        # Procesamiento de archivos entrantes
│   └── outbound/       # Envío al servidor externo
├── scripts/            # Utilidades y pruebas manuales
└── README_CONEXION.md  # Guía de conexión para clientes SFTP
```

## Datos de Conexión (Fase 1 ya desplegada)

- Endpoint SFTP: `s-c643d8f6b6dc4bc28.server.transfer.us-east-1.amazonaws.com`
- Puerto: `22`
- Usuario: `sftpuser`
- Clave privada (para FileZilla): `keys/sftp_user_key`
- Bucket: `workium-sftp-poc-sftp-poc-dev`

## Cambios aplicados (última validación Fase 1)

- `transfer_connector.tf`: `trusted_host_keys` del conector actualizado para que Transfer Family acepte el host key del servidor destino.
- `iam.tf` (role del conector): permisos añadidos para que el conector pueda leer el secret en Secrets Manager (`secretsmanager:GetSecretValue` + decrypt KMS).
- `lambdas/outbound/handler_outbound.py`: corrección del `start_file_transfer` para transferencias SFTP outbound usando `SendFilePaths` + `RemoteDirectoryPath` (ya no usa `RetrieveFilePaths`).
- Confirmación end-to-end:
  - Upload `pain_0001.txt` (SFTP → Transfer Family) genera `pain_0002.txt` en `s3://workium-sftp-poc-sftp-poc-dev/outbound/`
  - Transfer Family outbound para ese archivo queda en estado `COMPLETED`.

## Flujo de validación rápida

1. Subir `pain_0001.txt` al SFTP del Transfer Family (ver `README_CONEXION.md`).
2. Esperar ~15-60s.
3. Validar:
   - `aws s3 ls s3://workium-sftp-poc-sftp-poc-dev/outbound/`
   - `pain_0002.txt` contiene la marca `[OUTBOUND - procesado por Lambda Fase 1]`
   - El archivo se transfiere al servidor destino en `/upload/` (sftpcloud.io).

