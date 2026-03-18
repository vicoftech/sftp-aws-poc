output "transfer_family_endpoint" {
  description = "AWS Transfer Family SFTP endpoint"
  value       = aws_transfer_server.poc.endpoint
}

output "sftp_username" {
  description = "SFTP username for the external client"
  value       = "external-poc-user"
}

output "sftp_private_key_secret_arn" {
  description = "Secrets Manager ARN for the SFTP user's private SSH key"
  value       = aws_secretsmanager_secret.sftp_user_private_key.arn
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for inbound/outbound files"
  value       = aws_s3_bucket.poc.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for inbound/outbound files"
  value       = aws_s3_bucket.poc.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for encrypting secrets and S3 objects"
  value       = aws_kms_key.poc.arn
}

output "lambda_inbound_name" {
  description = "Name of the inbound Lambda function"
  value       = aws_lambda_function.inbound.function_name
}

output "lambda_inbound_log_group" {
  description = "CloudWatch Log Group for the inbound Lambda"
  value       = aws_cloudwatch_log_group.inbound.name
}

output "lambda_outbound_name" {
  description = "Name of the outbound Lambda function"
  value       = aws_lambda_function.outbound.function_name
}

output "lambda_outbound_log_group" {
  description = "CloudWatch Log Group for the outbound Lambda"
  value       = aws_cloudwatch_log_group.outbound.name
}

output "test_payload_pgp_path" {
  description = "Local path of the encrypted test payload file"
  value       = "${path.module}/test_files/test_payload.txt.pgp"
}

output "poc_validation_commands" {
  description = "Commands to validate the inbound and outbound flows"
  value       = <<-EOT
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
  EOT
}

