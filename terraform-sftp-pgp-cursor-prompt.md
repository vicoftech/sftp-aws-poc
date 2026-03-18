# Terraform POC — AWS Transfer Family + SFTP + PGP End-to-End
## Cursor AI Prompt — Implementación Completa

> **Cómo usar este archivo en Cursor:**
> 1. Abrí Cursor y creá una carpeta vacía `poc-sftp-pgp/`
> 2. Abrí el chat de Cursor (`Cmd/Ctrl + L`) o el modo **Composer** (`Cmd/Ctrl + I`)
> 3. Pegá el contenido de la sección **"PROMPT CURSOR"** directamente en el chat
> 4. Cursor leerá el contexto del workspace y generará todos los archivos
> 5. Revisá cada archivo generado antes de ejecutar `terraform init`

---

## PROMPT CURSOR

```
Eres un experto en Terraform, AWS y seguridad. Tu tarea es implementar una POC
completa de transferencia de archivos SFTP con cifrado PGP en AWS.

Genera TODOS los archivos necesarios en el workspace actual. Crea cada archivo
con su path completo relativo al proyecto. No omitas ningún archivo. Después de
generar cada archivo, confirmá qué archivo creaste y qué hace.

### FUENTE CANÓNICA OBLIGATORIA
Toda la infraestructura AWS debe basarse en:
  Módulo:  https://github.com/aws-ia/terraform-aws-transfer-family
  Ejemplo: examples/sftp-internet-facing-vpc-endpoint-service-managed-S3

Seguir SIEMPRE las convenciones del AWS IA Terraform Community:
- snake_case para todos los recursos e identificadores
- Archivos separados: main.tf, variables.tf, outputs.tf, versions.tf,
  locals.tf, s3.tf, iam.tf, lambda.tf, secrets.tf, transfer.tf, pgp_keys.tf
- Sin valores hardcodeados fuera de variables.tf y locals.tf
- Todos los recursos con bloque tags usando local.common_tags

---

### ESTRUCTURA DE ARCHIVOS A GENERAR

Crear exactamente esta estructura en el workspace:

  poc-sftp-pgp/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  ├── versions.tf
  ├── locals.tf
  ├── s3.tf
  ├── iam.tf
  ├── lambda.tf
  ├── secrets.tf
  ├── transfer.tf
  ├── pgp_keys.tf
  ├── test_file.tf
  ├── lambda/
  │   ├── inbound/
  │   │   ├── handler.py          ← descifrado PGP con pgpy
  │   │   └── requirements.txt    ← pgpy>=0.6.0, boto3
  │   └── outbound/
  │       ├── handler.py          ← cifrado PGP + envío SFTP con pgpy+paramiko
  │       └── requirements.txt    ← pgpy>=0.6.0, boto3, paramiko
  └── README.md                   ← instrucciones de uso y validación

---

### BLOQUE 1 — versions.tf

Generar con estos providers exactos:

  terraform {
    required_version = ">= 1.6.0"
    required_providers {
      aws     = { source = "hashicorp/aws",    version = ">= 5.30.0" }
      tls     = { source = "hashicorp/tls",    version = ">= 4.0.0"  }
      random  = { source = "hashicorp/random", version = ">= 3.6.0"  }
      null    = { source = "hashicorp/null",   version = ">= 3.2.0"  }
      local   = { source = "hashicorp/local",  version = ">= 2.4.0"  }
      archive = { source = "hashicorp/archive", version = ">= 2.4.0" }
    }
  }

  provider "aws" {
    region = var.aws_region
    default_tags {
      tags = {
        Project     = "poc-sftp-pgp"
        Environment = "poc"
        ManagedBy   = "terraform"
        Module      = "aws-ia/transfer-family"
      }
    }
  }

---

### BLOQUE 2 — variables.tf

  variable "aws_region"     { default = "us-east-1" }
  variable "project_name"   { default = "poc-sftp-pgp" }
  variable "pgp_passphrase" { default = ""; sensitive = true }

---

### BLOQUE 3 — locals.tf

  locals {
    common_tags          = { Project = var.project_name, Environment = "poc", ManagedBy = "terraform" }
    bucket_name          = "${var.project_name}-${random_id.suffix.hex}"
    lambda_inbound_name  = "${var.project_name}-inbound-decrypt"
    lambda_outbound_name = "${var.project_name}-outbound-encrypt"
    inbound_prefix       = "inbound/"
    outbound_prefix      = "outbound/"
  }

---

### BLOQUE 4 — pgp_keys.tf

Generar 2 pares de claves PGP autofirmadas RSA 4096 usando tls_private_key
y null_resource con local-exec gpg --batch --gen-key.

Par 1 — externo (simula cliente SFTP):
  - Nombre:  "SFTP External Client"
  - Email:   external@poc.local
  - Archivos: /tmp/poc_external_public.asc, /tmp/poc_external_private.asc

Par 2 — interno (simula AWS / Transfer Family):
  - Nombre:  "AWS Transfer Internal"
  - Email:   internal@poc.local
  - Archivos: /tmp/poc_internal_public.asc, /tmp/poc_internal_private.asc

Implementación con null_resource + local-exec:
  1. Crear archivo de parámetros GPG con templatefile()
  2. Ejecutar gpg --batch --gen-key <params_file>
  3. Exportar con gpg --armor --export y gpg --armor --export-secret-keys
  4. Leer con data "local_file"
  5. Almacenar en Secrets Manager (ver BLOQUE 6)

Las claves privadas NUNCA aparecen en outputs. Marcar sensitive=true.

También generar par SSH para el usuario SFTP:
  resource "tls_private_key" "sftp_user" {
    algorithm = "RSA"
    rsa_bits  = 4096
  }

Certificado autofirmado para la POC:
  resource "tls_self_signed_cert" "transfer_poc" {
    subject { common_name = "poc-sftp-transfer.local" }
    validity_period_hours = 8760
    is_ca_certificate     = true
    allowed_uses = ["key_encipherment","digital_signature","server_auth","cert_signing"]
  }
  resource "aws_acm_certificate" "transfer_poc" {
    private_key      = tls_private_key.transfer_poc.private_key_pem
    certificate_body = tls_self_signed_cert.transfer_poc.cert_pem
  }

---

### BLOQUE 5 — secrets.tf

Crear un KMS CMK dedicado para toda la POC:
  resource "aws_kms_key" "poc" { description = "POC SFTP PGP CMK" }
  resource "aws_kms_alias" "poc" { name = "alias/poc-sftp-pgp" }

Crear exactamente estos 5 secretos en Secrets Manager (todos con kms_key_id):

  1. "poc/pgp/external/private"  ← external_private.asc
  2. "poc/pgp/external/public"   ← external_public.asc
  3. "poc/pgp/internal/private"  ← internal_private.asc
  4. "poc/pgp/internal/public"   ← internal_public.asc
  5. "poc/sftp/user/ssh_key_private" ← tls_private_key.sftp_user.private_key_pem

Todos con recovery_window_in_days = 0 (POC — permite destruir sin espera).

---

### BLOQUE 6 — s3.tf

Bucket S3:
  - Nombre: local.bucket_name (con random_id de 4 bytes hex)
  - Versioning: ENABLED
  - SSE: aws:kms con el CMK de secrets.tf
  - Block all public access: true
  - Force destroy: true
  - Ownership controls: BucketOwnerPreferred
  - NO usar aws_s3_bucket_acl con canned ACLs (deprecated)

Objetos placeholder para crear prefijos:
  aws_s3_object "inbound_placeholder"  → key = "inbound/.keep",  content = ""
  aws_s3_object "outbound_placeholder" → key = "outbound/.keep", content = ""

Ciclo de vida (aws_s3_bucket_lifecycle_configuration):
  Regla "inbound-lifecycle":
    filter { prefix = "inbound/" }
    transition { days = 1; storage_class = "GLACIER_IR" }  ← mínimo S3 es 1 día
    expiration { days = 7 }
  Regla "outbound-lifecycle":
    filter { prefix = "outbound/" }
    transition { days = 1; storage_class = "GLACIER_IR" }
    expiration { days = 7 }

  IMPORTANTE: Agregar este comentario en el código:
  # NOTE: S3 Lifecycle minimum transition is 1 day — cannot use minutes.
  # For production, consider S3 Object Lock or EventBridge for finer control.

Notificaciones S3 → Lambda (aws_s3_bucket_notification):
  - s3:ObjectCreated:* en prefix "inbound/" con filter_suffix ".pgp"
    → lambda_inbound (aws_lambda_function.inbound.arn)
  - s3:ObjectCreated:* en prefix "outbound/" sin filter_suffix
    → lambda_outbound (aws_lambda_function.outbound.arn)
    (el handler filtra internamente archivos .pgp/.keep)

Agregar aws_lambda_permission para que S3 pueda invocar cada Lambda.
Usar depends_on = [aws_s3_bucket_notification] en los recursos dependientes.

---

### BLOQUE 7 — iam.tf

Role 1: poc-transfer-family-role
  Trust: transfer.amazonaws.com
  Permisos:
    - s3:PutObject, GetObject, DeleteObject, GetBucketLocation en bucket/*
    - s3:ListBucket en bucket
    - logs:CreateLogGroup, CreateLogStream, PutLogEvents

Role 2: poc-lambda-inbound-role
  Trust: lambda.amazonaws.com
  Permisos:
    - s3:GetObject, PutObject, DeleteObject en bucket/inbound/*
    - secretsmanager:GetSecretValue en poc/pgp/internal/private
    - secretsmanager:GetSecretValue en poc/pgp/external/public
    - kms:Decrypt, GenerateDataKey
    - logs:* en /aws/lambda/poc-sftp-pgp-inbound-*
  Managed: AWSLambdaBasicExecutionRole

Role 3: poc-lambda-outbound-role
  Trust: lambda.amazonaws.com
  Permisos:
    - s3:GetObject, PutObject, DeleteObject en bucket/outbound/*
    - secretsmanager:GetSecretValue en poc/pgp/external/public
    - secretsmanager:GetSecretValue en poc/sftp/user/ssh_key_private
    - kms:Decrypt, GenerateDataKey
    - logs:* en /aws/lambda/poc-sftp-pgp-outbound-*
  Managed: AWSLambdaBasicExecutionRole

---

### BLOQUE 8 — lambda.tf

Empaquetar cada Lambda con archive_file (data source):
  - source_dir  = "${path.module}/lambda/inbound"
  - output_path = "${path.module}/.terraform/lambda_inbound.zip"

Lambda Inbound (descifrado):
  function_name = local.lambda_inbound_name
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 300
  memory_size   = 512
  ephemeral_storage { size = 1024 }
  environment variables:
    INTERNAL_PRIVATE_KEY_SECRET_ARN = aws_secretsmanager_secret.internal_private.arn
    EXTERNAL_PUBLIC_KEY_SECRET_ARN  = aws_secretsmanager_secret.external_public.arn
    S3_BUCKET_NAME                  = aws_s3_bucket.poc.id
    PGP_PASSPHRASE                  = var.pgp_passphrase

Lambda Outbound (cifrado + envío):
  function_name = local.lambda_outbound_name
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 300
  memory_size   = 512
  ephemeral_storage { size = 1024 }
  environment variables:
    EXTERNAL_PUBLIC_KEY_SECRET_ARN  = aws_secretsmanager_secret.external_public.arn
    INTERNAL_PRIVATE_KEY_SECRET_ARN = aws_secretsmanager_secret.internal_private.arn
    TRANSFER_FAMILY_ENDPOINT        = module.transfer_family.server_endpoint
    SFTP_USERNAME                   = "external-poc-user"
    SFTP_PRIVATE_KEY_SECRET_ARN     = aws_secretsmanager_secret.sftp_user_private_key.arn
    S3_BUCKET_NAME                  = aws_s3_bucket.poc.id

CloudWatch Log Groups (retención 7 días) para cada Lambda.

---

### BLOQUE 9 — transfer.tf

Usar el módulo oficial:
  module "transfer_family" {
    source  = "aws-ia/transfer-family/aws"
    version = ">= 1.0.0"

    server_name            = "${var.project_name}-server"
    domain                 = "S3"
    protocols              = ["SFTP"]
    endpoint_type          = "PUBLIC"
    identity_provider_type = "SERVICE_MANAGED"
    logging_role           = aws_iam_role.transfer_logging.arn

    s3_buckets = {
      poc_bucket = {
        bucket_name = aws_s3_bucket.poc.id
        prefix      = ""
      }
    }

    users = {
      external_client = {
        user_name           = "external-poc-user"
        role                = aws_iam_role.transfer_family.arn
        home_directory_type = "LOGICAL"
        home_directory_mappings = [
          { entry = "/", target = "/${aws_s3_bucket.poc.id}/inbound" }
        ]
        ssh_public_keys = [tls_private_key.sftp_user.public_key_openssh]
      }
    }

    tags = local.common_tags
  }

Agregar time_sleep de 120 segundos después del módulo (Transfer Family tarda
en estar disponible tras el apply):
  resource "time_sleep" "wait_transfer_ready" {
    depends_on      = [module.transfer_family]
    create_duration = "120s"
  }

Si el módulo aws-ia no soporta endpoint PUBLIC sin VPC, crear directamente:
  resource "aws_transfer_server" "poc" { ... }
  resource "aws_transfer_user" "external" { ... }
  resource "aws_transfer_ssh_key" "external" { ... }
  (documentar esta decisión con un comentario # FALLBACK: módulo no compatible)

---

### BLOQUE 10 — test_file.tf

Crear archivo de prueba con contenido conocido y determinístico:

  locals {
    test_file_content = <<-EOT
      POC_TEST_FILE_v1
      timestamp: ${timestamp()}
      content: HELLO_FROM_EXTERNAL_CLIENT
      checksum_word: TRANSFER_FAMILY_PGP_OK
    EOT
  }

  resource "local_file" "test_plain" {
    filename = "${path.module}/test_files/test_payload_plain.txt"
    content  = local.test_file_content
  }

Cifrar el archivo con la clave pública interna usando null_resource + local-exec:
  gpg --batch --yes --trust-model always \
      --encrypt --armor \
      --recipient internal@poc.local \
      --output test_files/test_payload.txt.pgp \
      test_files/test_payload_plain.txt

Crear también test_files/test_outbound_plain.txt para el flujo de salida:
  resource "local_file" "test_outbound" {
    filename = "${path.module}/test_files/test_outbound_plain.txt"
    content  = "OUTBOUND_TEST_FILE\ncontent: HELLO_TO_EXTERNAL_CLIENT\n"
  }

---

### BLOQUE 11 — lambda/inbound/handler.py

Generar el handler completo usando pgpy (NO python-gnupg, NO subprocess gpg):

```python
"""
Lambda: Inbound PGP Decryption
Trigger: S3 ObjectCreated on prefix inbound/*.pgp
Source: https://github.com/aws-ia/terraform-aws-transfer-family
"""
import boto3
import pgpy
import os
import json
import logging
from pgpy.constants import PubKeyAlgorithm, KeyFlags, HashAlgorithm, SymmetricKeyAlgorithm, CompressionAlgorithm

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
sm_client = boto3.client('secretsmanager')

def get_secret(secret_arn: str) -> str:
    response = sm_client.get_secret_value(SecretId=secret_arn)
    return response['SecretString']

def handler(event, context):
    results = []

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key    = record['s3']['object']['key']

        # Skip placeholders and already-decrypted files
        if key.endswith('.keep') or '_decrypted' in key:
            logger.info(f"Skipping: {key}")
            continue

        logger.info(f"[INBOUND] Processing: s3://{bucket}/{key}")

        try:
            # 1. Load internal private key from Secrets Manager
            private_key_pem = get_secret(os.environ['INTERNAL_PRIVATE_KEY_SECRET_ARN'])
            private_key, _ = pgpy.PGPKey.from_blob(private_key_pem)

            # 2. Download encrypted file from S3
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            encrypted_data = obj['Body'].read().decode('utf-8')

            # 3. Load encrypted message
            pgp_message = pgpy.PGPMessage.from_blob(encrypted_data)

            # 4. Decrypt
            passphrase = os.environ.get('PGP_PASSPHRASE', '')
            with private_key.unlock(passphrase) if passphrase else private_key.ctx():
                decrypted = private_key.decrypt(pgp_message)

            decrypted_content = decrypted.message
            if isinstance(decrypted_content, (bytes, bytearray)):
                decrypted_content = decrypted_content.decode('utf-8')

            logger.info(f"[INBOUND] Decryption SUCCESS for: {key}")

            # 5. POC Validation
            if 'TRANSFER_FAMILY_PGP_OK' in decrypted_content:
                logger.info("[INBOUND] POC VALIDATION PASSED ✓ checksum_word found")
            else:
                logger.warning("[INBOUND] checksum_word not found — may not be the test payload")

            # 6. Upload decrypted file to S3 inbound/
            decrypted_key = key.replace('.pgp', '_decrypted.txt').replace('.gpg', '_decrypted.txt')
            s3_client.put_object(
                Bucket=bucket,
                Key=decrypted_key,
                Body=decrypted_content.encode('utf-8'),
                Metadata={
                    'original-file': key,
                    'decryption-status': 'success',
                    'poc-validation': 'PASSED' if 'TRANSFER_FAMILY_PGP_OK' in decrypted_content else 'UNKNOWN'
                }
            )

            logger.info(f"[INBOUND] Decrypted file saved to: s3://{bucket}/{decrypted_key}")
            results.append({'file': key, 'status': 'decrypted', 'output': decrypted_key})

        except Exception as e:
            logger.error(f"[INBOUND] FAILED for {key}: {str(e)}", exc_info=True)
            raise

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Inbound decryption completed', 'results': results})
    }
```

---

### BLOQUE 12 — lambda/outbound/handler.py

```python
"""
Lambda: Outbound PGP Encryption + SFTP Send
Trigger: S3 ObjectCreated on prefix outbound/ (non-pgp files)
Source: https://github.com/aws-ia/terraform-aws-transfer-family
"""
import boto3
import pgpy
import paramiko
import os
import json
import logging
from io import BytesIO
from pgpy.constants import PubKeyAlgorithm, KeyFlags, HashAlgorithm, SymmetricKeyAlgorithm, CompressionAlgorithm

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
sm_client = boto3.client('secretsmanager')

def get_secret(secret_arn: str) -> str:
    response = sm_client.get_secret_value(SecretId=secret_arn)
    return response['SecretString']

def handler(event, context):
    results = []

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key    = record['s3']['object']['key']

        # Skip already-encrypted files, placeholders, and metadata files
        if key.endswith(('.pgp', '.gpg', '.keep')) or '_encrypted' in key:
            logger.info(f"Skipping already-processed: {key}")
            continue

        logger.info(f"[OUTBOUND] Processing for encryption: s3://{bucket}/{key}")

        try:
            # 1. Load external public key from Secrets Manager
            pub_key_pem = get_secret(os.environ['EXTERNAL_PUBLIC_KEY_SECRET_ARN'])
            pub_key, _ = pgpy.PGPKey.from_blob(pub_key_pem)

            # 2. Download plaintext file from S3
            obj = s3_client.get_object(Bucket=bucket, Key=key)
            plain_data = obj['Body'].read()

            if isinstance(plain_data, (bytes, bytearray)):
                plain_text = plain_data.decode('utf-8')
            else:
                plain_text = plain_data

            # 3. Create PGP message and encrypt with external public key
            pgp_message = pgpy.PGPMessage.new(plain_text)
            encrypted_message = pub_key.encrypt(pgp_message)
            encrypted_content = str(encrypted_message).encode('utf-8')

            logger.info(f"[OUTBOUND] Encryption SUCCESS for: {key}")

            # 4. Upload encrypted file to S3 outbound/
            encrypted_key = key + '.pgp'
            s3_client.put_object(
                Bucket=bucket,
                Key=encrypted_key,
                Body=encrypted_content,
                Metadata={
                    'original-file': key,
                    'encryption-status': 'success',
                    'recipient': 'external@poc.local'
                }
            )
            logger.info(f"[OUTBOUND] Encrypted file saved: s3://{bucket}/{encrypted_key}")

            # 5. Push encrypted file via SFTP (Lambda → Transfer Family endpoint)
            # Pattern: Lambda pushes to Transfer Family so external client can pull.
            # NOTE: Transfer Family is primarily inbound. For true outbound push to
            # an external SFTP server, replace sftp_host with the external server.
            # Ref: https://github.com/aws-ia/terraform-aws-transfer-family
            try:
                sftp_host    = os.environ['TRANSFER_FAMILY_ENDPOINT']
                sftp_user    = os.environ['SFTP_USERNAME']
                sftp_key_arn = os.environ['SFTP_PRIVATE_KEY_SECRET_ARN']

                ssh_key_pem = get_secret(sftp_key_arn)
                pkey = paramiko.RSAKey.from_private_key(BytesIO(ssh_key_pem.encode()))

                ssh = paramiko.SSHClient()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(hostname=sftp_host, username=sftp_user, pkey=pkey, timeout=30)

                sftp = ssh.open_sftp()
                remote_path = f"/{os.path.basename(encrypted_key)}"

                with sftp.open(remote_path, 'wb') as remote_file:
                    remote_file.write(encrypted_content)

                sftp.close()
                ssh.close()

                logger.info(f"[OUTBOUND] File sent via SFTP to: {sftp_host}:{remote_path}")
                results.append({'file': key, 'status': 'encrypted_and_sent', 'output': encrypted_key})

            except Exception as sftp_error:
                # Non-fatal: file is already in S3, SFTP push is best-effort for POC
                logger.warning(f"[OUTBOUND] SFTP push failed (non-fatal for POC): {sftp_error}")
                results.append({'file': key, 'status': 'encrypted_s3_only', 'output': encrypted_key})

        except Exception as e:
            logger.error(f"[OUTBOUND] FAILED for {key}: {str(e)}", exc_info=True)
            raise

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Outbound encryption completed', 'results': results})
    }
```

---

### BLOQUE 13 — outputs.tf

Generar todos estos outputs:

  transfer_family_endpoint       → module.transfer_family.server_endpoint
  sftp_username                  → "external-poc-user"
  sftp_private_key_secret_arn    → sensitive = true
  s3_bucket_name                 → aws_s3_bucket.poc.id
  s3_bucket_arn                  → aws_s3_bucket.poc.arn
  kms_key_arn                    → aws_kms_key.poc.arn
  lambda_inbound_name            → aws_lambda_function.inbound.function_name
  lambda_inbound_log_group       → aws_cloudwatch_log_group.inbound.name
  lambda_outbound_name           → aws_lambda_function.outbound.function_name
  lambda_outbound_log_group      → aws_cloudwatch_log_group.outbound.name
  test_payload_pgp_path          → path local del archivo de prueba cifrado
  poc_validation_commands        → string heredoc con comandos completos (ver abajo)

El output poc_validation_commands debe contener estos comandos exactos:

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

---

### BLOQUE 14 — README.md

Generar un README completo con:

  # Secciones requeridas:
  ## Arquitectura
  ## Pre-requisitos (aws cli, terraform >= 1.6, gpg instalado localmente)
  ## Variables de configuración
  ## Deploy
    terraform init
    terraform plan -out=poc.tfplan
    terraform apply poc.tfplan
  ## Validación (copiar los comandos del output poc_validation_commands)
  ## Limitaciones conocidas de la POC
    - S3 Lifecycle mínimo es 1 día (no 10 minutos)
    - Transfer Family endpoint puede tardar 2-5 min en estar disponible
    - Certificado autofirmado — no usar en producción
    - gnupg binary no disponible en Lambda runtime → se usa pgpy (pura Python)
  ## Destroy
    terraform destroy -auto-approve
  ## Referencias
    - https://github.com/aws-ia/terraform-aws-transfer-family
    - https://registry.terraform.io/modules/aws-ia/transfer-family/aws

---

### RESTRICCIONES CRÍTICAS PARA CURSOR

1. NO usar aws_s3_bucket_acl con private/public-read. Usar
   aws_s3_bucket_ownership_controls + aws_s3_bucket_public_access_block.

2. NO hardcodear ARNs, account IDs ni region fuera de data sources o variables.
   Usar data "aws_caller_identity" y data "aws_region" donde sea necesario.

3. NO usar python-gnupg en las Lambdas (requiere binario gpg no disponible
   en Python 3.12 runtime). Usar pgpy >= 0.6.0 exclusivamente.

4. El ciclo de vida S3 en minutos NO es posible en AWS. Mínimo = 1 día.
   Configurar 1 día + comentario explicando la limitación.

5. aws_s3_bucket_notification tiene dependency issues. Siempre agregar:
   depends_on = [aws_lambda_permission.allow_s3_inbound,
                 aws_lambda_permission.allow_s3_outbound]

6. Las claves privadas PGP y SSH deben ser sensitive = true en todos
   los recursos donde aparezcan. Nunca en outputs sin sensitive = true.

7. Agregar time_sleep de 120s después de module.transfer_family antes
   de cualquier recurso que use module.transfer_family.server_endpoint.

8. Si el módulo aws-ia/transfer-family no soporta PUBLIC endpoint sin VPC,
   crear aws_transfer_server, aws_transfer_user y aws_transfer_ssh_key
   directamente y documentarlo con un comentario # FALLBACK.

9. Todos los archivos lambda/ deben tener sus requirements.txt con
   versiones pinneadas: pgpy==0.6.0, paramiko==3.4.0, boto3==1.34.0

10. Generar TODOS los archivos de una vez. No preguntar por confirmación
    entre archivos. Crear la estructura completa en un solo paso.

---

### CRITERIOS DE ACEPTACIÓN

La implementación es correcta cuando:

  ✅ terraform init sin errores de providers
  ✅ terraform validate sin errores
  ✅ terraform plan muestra ~35-45 recursos a crear
  ✅ Sin valores hardcodeados fuera de variables.tf y locals.tf
  ✅ Todas las claves privadas marcadas sensitive = true
  ✅ Los 2 handlers Lambda importan pgpy (no gnupg)
  ✅ requirements.txt de ambas Lambdas tiene versiones pinneadas
  ✅ README.md contiene comandos de validación completos
  ✅ outputs.tf tiene poc_validation_commands con los 8 comandos de validación

Después de generar todos los archivos, ejecutá:
  terraform init && terraform validate
Y reportá el resultado.
```

---

## Diagrama de arquitectura

```
Cliente SFTP externo
       │
       │  SFTP (puerto 22)
       ▼
┌─────────────────────┐
│  AWS Transfer Family │  ← endpoint PUBLIC + usuario SSH
│  (aws-ia module)     │
└──────────┬──────────┘
           │ PutObject
           ▼
┌─────────────────────────────────────────────────────────────┐
│  S3 Bucket (SSE-KMS)                                         │
│                                                              │
│  /inbound/*.pgp  ──── S3 Event ──► Lambda Inbound           │
│                                    (pgpy decrypt)            │
│                                    └── /inbound/*_decrypted  │
│                                                              │
│  /outbound/*.txt ──── S3 Event ──► Lambda Outbound          │
│                                    (pgpy encrypt)            │
│                                    └── /outbound/*.pgp       │
└──────────────────────────────┬──────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
     Secrets Manager     KMS CMK         CloudWatch Logs
     ┌──────────────┐                    /aws/lambda/
     │ pgp/ext/pub  │
     │ pgp/ext/priv │
     │ pgp/int/pub  │
     │ pgp/int/priv │
     │ sftp/ssh_key │
     └──────────────┘
```

## Flujos de validación

### Flujo 6.1 — INBOUND (descifrado)
```
[Cliente externo]                    [AWS]
      │                                │
      │── test_payload.txt.pgp ──SFTP─►│── Transfer Family
      │                                │        │ PutObject
      │                                │        ▼
      │                                │   S3 /inbound/
      │                                │        │ S3 Event
      │                                │        ▼
      │                                │   Lambda Inbound
      │                                │   (pgpy.decrypt)
      │                                │        │ PutObject
      │                                │        ▼
      │                   VALIDAR ◄────│   S3 /inbound/test_payload_decrypted.txt
      │               "TRANSFER_FAMILY_PGP_OK" en contenido
```

### Flujo 6.2 — OUTBOUND (cifrado)
```
[AWS CLI / app]                      [AWS]                    [Cliente externo]
      │                                │                              │
      │── aws s3 cp plaintext ────────►│── S3 /outbound/              │
      │                                │        │ S3 Event             │
      │                                │        ▼                     │
      │                                │   Lambda Outbound             │
      │                                │   (pgpy.encrypt)              │
      │                                │        │ PutObject            │
      │                                │        ▼                     │
      │                                │   S3 /outbound/*.pgp          │
      │                                │        │ SFTP put             │
      │                                │        ▼                     │
      │                                │   Transfer Family ──────────►│
      │                                │                   archivo.pgp│
```

## Notas de implementación importantes

| Aspecto | Decisión POC | Razón |
|---|---|---|
| Cifrado PGP en Lambda | `pgpy` (pura Python) | El binario `gpg` no está disponible en Python 3.12 runtime |
| Ciclo de vida S3 | 1 día → GLACIER_IR | S3 Lifecycle mínimo es 1 día; no acepta minutos |
| Certificado TLS | Autofirmado con `tls_self_signed_cert` | POC sin dominio real |
| Claves PGP | Generadas con `gpg --batch` local-exec | Provider gnupg no disponible en Terraform Registry para todas las versiones |
| Outbound SFTP | Lambda + Paramiko | Transfer Family es principalmente inbound; AS2 Connector para producción |
| Secretos | Secrets Manager + KMS CMK | Nunca en tfstate en texto plano |

## Referencia oficial

Módulo base: [aws-ia/terraform-aws-transfer-family](https://github.com/aws-ia/terraform-aws-transfer-family)  
Ejemplo canónico: `examples/sftp-internet-facing-vpc-endpoint-service-managed-S3`  
Registry: `registry.terraform.io/modules/aws-ia/transfer-family/aws`
