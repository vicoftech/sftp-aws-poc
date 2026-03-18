resource "aws_kms_key" "poc" {
  description = "POC SFTP PGP CMK"

  tags = local.common_tags
}

resource "aws_kms_alias" "poc" {
  name          = "alias/poc-sftp-pgp"
  target_key_id = aws_kms_key.poc.key_id
}

resource "aws_secretsmanager_secret" "external_private" {
  name                    = "poc/pgp/external/private"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "external_private" {
  secret_id     = aws_secretsmanager_secret.external_private.id
  secret_string = data.local_file.external_private.content
}

resource "aws_secretsmanager_secret" "external_public" {
  name                    = "poc/pgp/external/public"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "external_public" {
  secret_id     = aws_secretsmanager_secret.external_public.id
  secret_string = data.local_file.external_public.content
}

resource "aws_secretsmanager_secret" "internal_private" {
  name                    = "poc/pgp/internal/private"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "internal_private" {
  secret_id     = aws_secretsmanager_secret.internal_private.id
  secret_string = data.local_file.internal_private.content
}

resource "aws_secretsmanager_secret" "internal_public" {
  name                    = "poc/pgp/internal/public"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "internal_public" {
  secret_id     = aws_secretsmanager_secret.internal_public.id
  secret_string = data.local_file.internal_public.content
}

resource "aws_secretsmanager_secret" "sftp_user_private_key" {
  name                    = "poc/sftp/user/ssh_key_private"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "sftp_user_private_key" {
  secret_id     = aws_secretsmanager_secret.sftp_user_private_key.id
  # Use the manually generated external_client private key from C:\Temp
  secret_string = data.local_file.sftp_user_private.content
}

