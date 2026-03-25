locals {
  sftp_connector_private_key_pem = <<-EOT
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQQOqcK/SO0Tvyk3QKTJsheL+QZvGOnl
wOlFLXTSFFCDSPwqKdxPIXjOddUG9GX+2uNRdqOZLpdnhnhDXMc7NYLuAAAAqMalweLGpc
HiAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBA6pwr9I7RO/KTdA
pMmyF4v5Bm8Y6eXA6UUtdNIUUINI/Cop3E8heM511Qb0Zf7a41F2o5kul2eGeENcxzs1gu
4AAAAgIA6mAI+WKz1CVPfNIyaBQKNPMFB36IduvNxzdGbEvrYAAAAMc2Z0cGNsb3VkLmlv
AQIDBA==
-----END OPENSSH PRIVATE KEY-----
EOT
}

resource "aws_secretsmanager_secret" "sftp_connector_creds" {
  name                    = "${var.project_name}/sftp-connector/credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sftp_connector_creds" {
  secret_id = aws_secretsmanager_secret.sftp_connector_creds.id

  secret_string = jsonencode({
    Username   = "ca43baf534464d49a233683bd17fff1f"
    Password   = "FENqsXOUlkWu9yb763W5grPSmRCQ9Xsp"
    PrivateKey = local.sftp_connector_private_key_pem
  })
}

resource "aws_transfer_connector" "sftp_outbound" {
  url = "sftp://us-east-1.sftpcloud.io"

  sftp_config {
    user_secret_id = aws_secretsmanager_secret.sftp_connector_creds.arn

    trusted_host_keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBELYopkHc6vi++AqprGSo00zclDui4Ywj08QrnZgkLOF9v8PX8nlNErFMpnq9XyDGhYTKcWK/NtmeHYJIeQ89XM="
    ]
  }

  access_role  = aws_iam_role.transfer_connector_role.arn
  logging_role = aws_iam_role.transfer_family_cloudwatch.arn

  tags = {
    Name        = "${var.project_name}-sftp-connector"
    Environment = var.environment
  }
}

