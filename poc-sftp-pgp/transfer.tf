resource "time_sleep" "wait_transfer_ready" {
  depends_on      = [aws_transfer_server.poc]
  create_duration = "120s"
}

# FALLBACK: módulo aws-ia/transfer-family no compatible con PUBLIC endpoint en esta versión.
# Se crean directamente los recursos aws_transfer_server, aws_transfer_user y aws_transfer_ssh_key.

resource "aws_transfer_server" "poc" {
  identity_provider_type = "SERVICE_MANAGED"
  protocols              = ["SFTP"]
  domain                 = "S3"
  endpoint_type          = "PUBLIC"
  logging_role           = aws_iam_role.transfer_logging.arn

  tags = local.common_tags
}

resource "aws_transfer_ssh_key" "external" {
  server_id = aws_transfer_server.poc.id
  user_name = "external-poc-user"
  # Use the manually generated external_client public key from C:\Temp
  body = data.local_file.sftp_user_public.content

  depends_on = [
    aws_transfer_user.external
  ]
}

resource "aws_transfer_user" "external" {
  server_id = aws_transfer_server.poc.id
  user_name = "external-poc-user"
  role      = aws_iam_role.transfer_family.arn

  home_directory_type = "LOGICAL"

  home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.poc.id}"
  }

  tags = local.common_tags
}


