## Arquitectura

Esta POC implementa un flujo de transferencia de archivos SFTP usando **AWS Transfer Family** con backend en **S3** y cifrado/descifrado **PGP** manejado por funciones **AWS Lambda**.

- **Cliente SFTP externo** se conecta por SFTP a un endpoint público de AWS Transfer Family.
- **Transfer Family** escribe y lee archivos en un **bucket S3** cifrado con **SSE-KMS**.
- Cuando llegan archivos cifrados (`*.pgp`) al prefijo `inbound/`, una **Lambda Inbound** los descifra usando **pgpy** y almacena la versión plana en `inbound/*_decrypted.txt`.
- Cuando se suben archivos planos a `outbound/`, una **Lambda Outbound** los cifra con PGP y los deja como `outbound/*.pgp`, además de intentar enviarlos por SFTP hacia el endpoint de Transfer Family.
- Todas las claves PGP y la clave SSH del usuario SFTP se guardan en **AWS Secrets Manager** protegidos por un **KMS CMK** dedicado.

## Pre-requisitos

- **Terraform** `>= 1.6.0`
- **AWS CLI** configurado (perfil y credenciales con permisos suficientes para crear Transfer Family, S3, KMS, Secrets Manager, Lambda, IAM, ACM).
- **gpg** instalado localmente (para generación/cifrado de archivos de prueba vía `null_resource` + `local-exec`).
- Acceso a Internet para descarga de providers de Terraform y módulos.

## Variables de configuración

Las variables principales se definen en `variables.tf`:

- **`aws_region`**: región AWS donde se desplegará la POC (por defecto `us-east-1`).
- **`project_name`**: prefijo base para nombres de recursos (por defecto `poc-sftp-pgp`).
- **`pgp_passphrase`**: passphrase opcional para las claves PGP (sensitive).

Puedes sobreescribirlas con:

```bash
terraform plan -var="aws_region=us-east-1" -var="project_name=poc-sftp-pgp"
```

## Deploy

Desde la carpeta `poc-sftp-pgp/`:

```bash
terraform init
terraform plan -out=poc.tfplan
terraform apply poc.tfplan
```

Ten en cuenta:

- La primera ejecución de `terraform apply` tardará varios minutos (creación de Transfer Family, propagación de endpoint, etc.).
- El módulo `aws-ia/transfer-family` se descarga automáticamente desde el Registry.

## Validación

Tras el `apply`, Terraform expone en `outputs` un heredoc con los comandos de validación bajo el output `poc_validation_commands`. El contenido es el siguiente:

```bash
=== VALIDACIÓN 6.1 — Flujo INBOUND (cliente externo → AWS descifra) ===

# 1. Obtener clave SSH privada del usuario SFTP
aws secretsmanager get-secret-value \
  --secret-id poc/sftp/user/ssh_key_private \
  --query SecretString --output text > /tmp/sftp_user.pem
chmod 600 /tmp/sftp_user.pem

# 2. Subir archivo cifrado de prueba por SFTP
sftp -i /tmp/sftp_user.pem \
  external-poc-user@<TRANSFER_ENDPOINT> <<EOF
put test_files/test_payload.txt.pgp
EOF

# 3. Verificar que Lambda descifró el archivo (esperar ~30 segundos)
aws s3 ls s3://<BUCKET>/inbound/ --recursive
# Esperado: test_payload_decrypted.txt

# 4. Ver contenido descifrado y validar checksum
aws s3 cp s3://<BUCKET>/inbound/test_payload_decrypted.txt -
# Esperado: contiene "TRANSFER_FAMILY_PGP_OK"

=== VALIDACIÓN 6.2 — Flujo OUTBOUND (AWS cifra → cliente externo descarga) ===

# 1. Subir archivo plano al prefijo outbound
aws s3 cp test_files/test_outbound_plain.txt \
  s3://<BUCKET>/outbound/test_outbound_plain.txt

# 2. Verificar que Lambda cifró el archivo (esperar ~30 segundos)
aws s3 ls s3://<BUCKET>/outbound/ --recursive
# Esperado: test_outbound_plain.txt.pgp

# 3. Descargar archivo cifrado como cliente externo
sftp -i /tmp/sftp_user.pem \
  external-poc-user@<TRANSFER_ENDPOINT> <<EOF
get test_outbound_plain.txt.pgp /tmp/
EOF

# 4. Descifrar localmente con clave privada externa
aws secretsmanager get-secret-value \
  --secret-id poc/pgp/external/private \
  --query SecretString --output text > /tmp/external_private.asc
gpg --import /tmp/external_private.asc
gpg --decrypt /tmp/test_outbound_plain.txt.pgp
```

Sustituye:

- `<TRANSFER_ENDPOINT>` por el valor del output `transfer_family_endpoint`.
- `<BUCKET>` por el valor del output `s3_bucket_name`.

## Limitaciones conocidas de la POC

- **S3 Lifecycle mínimo es 1 día**: no es posible configurar expiración o transición en minutos. En la POC se usa 1 día hacia `GLACIER_IR` y expiración a los 7 días.
- **Transfer Family endpoint puede tardar 2–5 minutos** en estar disponible después del `apply`. Por eso se añadió un `time_sleep` de 120 segundos antes de que la Lambda Outbound utilice el endpoint.
- **Certificado TLS autofirmado** (`tls_self_signed_cert` + `aws_acm_certificate`): válido solo para laboratorio; no usar en producción.
- **Binario `gpg` no disponible en Lambda**: el cifrado/descifrado en Lambda se hace con `pgpy` (pura Python). `gpg` solo se usa localmente vía `null_resource` para generar claves y archivos de prueba.
- **Uso de Transfer Family principalmente inbound**: el flujo outbound que envía archivos por SFTP desde Lambda es de mejor esfuerzo y solo para demostración.

## Destroy

Para destruir todos los recursos de la POC:

```bash
terraform destroy -auto-approve
```

Recuerda que:

- Los secretos en Secrets Manager se crean con `recovery_window_in_days = 0`, por lo que se eliminan sin periodo de recuperación (adecuado para POC).
- El bucket S3 tiene `force_destroy = true`, por lo que se borran todos los objetos.

## Referencias

- Módulo Transfer Family: `https://github.com/aws-ia/terraform-aws-transfer-family`
- Registry Terraform: `https://registry.terraform.io/modules/aws-ia/transfer-family/aws`

