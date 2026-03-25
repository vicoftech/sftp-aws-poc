resource "aws_transfer_server" "sftp" {
  protocols              = ["SFTP"]
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "PUBLIC"
  logging_role           = aws_iam_role.transfer_family_cloudwatch.arn

  tags = {
    Name        = "${var.project_name}-sftp-server"
    Environment = var.environment
    Phase       = "1"
  }
}

# Usuario SFTP — el cliente externo se conecta con clave privada
resource "aws_transfer_user" "sftp_user" {
  server_id           = aws_transfer_server.sftp.id
  user_name           = var.sftp_username
  role                = aws_iam_role.transfer_family_role.arn
  home_directory_type = "PATH"
  home_directory      = "/${aws_s3_bucket.sftp_poc.bucket}/inbound"

  tags = {
    Name = "${var.project_name}-sftp-user"
  }
}

# Clave pública SSH del usuario — generada con scripts/generate_sftp_keys.sh
resource "aws_transfer_ssh_key" "sftp_user_key" {
  server_id = aws_transfer_server.sftp.id
  user_name = aws_transfer_user.sftp_user.user_name
  body       = var.sftp_user_public_key
}

