resource "aws_kms_key" "poc" {
  description = "POC SFTP symmetric CMK for S3/Secrets"

  tags = local.common_tags
}

resource "aws_kms_alias" "poc" {
  name          = "alias/poc-sftp-pgp"
  target_key_id = aws_kms_key.poc.key_id
}

# Asymmetric KMS key used by Lambdas for encrypt/decrypt (standard AWS algorithm)
resource "aws_kms_key" "poc_asymmetric" {
  description = "POC SFTP asymmetric CMK for end-to-end encryption"
  customer_master_key_spec = "RSA_4096"
  key_usage                = "ENCRYPT_DECRYPT"

  tags = local.common_tags
}

resource "aws_kms_alias" "poc_asymmetric" {
  name          = "alias/poc-sftp-pgp-asym"
  target_key_id = aws_kms_key.poc_asymmetric.key_id
}

# Secret that keeps the logical reference to the asymmetric KMS key.
# From the Lambda perspective, the key identifier lives in Secrets Manager,
# while the actual key material is isolated inside KMS.
resource "aws_secretsmanager_secret" "kms_asymmetric_key" {
  name                    = "poc/kms/asymmetric/key-id"
  kms_key_id              = aws_kms_key.poc.arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "kms_asymmetric_key" {
  secret_id     = aws_secretsmanager_secret.kms_asymmetric_key.id
  secret_string = aws_kms_key.poc_asymmetric.key_id
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

