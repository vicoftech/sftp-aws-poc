data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}

locals {
  log_resource_arn = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
  s3_kms_key_arn    = data.aws_kms_alias.s3.target_key_arn
  secrets_kms_key_arn = data.aws_kms_alias.secretsmanager.target_key_arn
}

#
# Transfer Family (SFTP Server)
#
resource "aws_iam_role" "transfer_family_role" {
  name = "${var.project_name}-transfer-family-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "transfer_family_policy" {
  statement {
    sid     = "S3InboundPut"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/inbound/*"
    ]
  }

  statement {
    sid     = "S3OutboundGet"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/outbound/*"
    ]
  }

  statement {
    sid     = "S3ListAndLocation"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.sftp_poc.arn
    ]
  }

  # Permisos KMS necesarios para leer/escribir objetos cifrados en el bucket.
  statement {
    sid     = "S3KmsAccess"
    effect  = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [local.s3_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "transfer_family_role_policy" {
  name   = "${var.project_name}-transfer-family-policy-${var.environment}"
  role   = aws_iam_role.transfer_family_role.id
  policy = data.aws_iam_policy_document.transfer_family_policy.json
}

#
# Transfer Family Logging Role
#
resource "aws_iam_role" "transfer_family_cloudwatch" {
  name = "${var.project_name}-transfer-family-logs-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "transfer_family_cloudwatch_policy" {
  statement {
    sid     = "CloudWatchLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.log_resource_arn]
  }
}

resource "aws_iam_role_policy" "transfer_family_cloudwatch_role_policy" {
  name   = "${var.project_name}-transfer-family-cloudwatch-policy-${var.environment}"
  role   = aws_iam_role.transfer_family_cloudwatch.id
  policy = data.aws_iam_policy_document.transfer_family_cloudwatch_policy.json
}

#
# Transfer Family Connector (SFTP salida)
#
resource "aws_iam_role" "transfer_connector_role" {
  name = "${var.project_name}-transfer-connector-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "transfer_connector_policy" {
  statement {
    sid     = "ConnectorS3OutboundAccess"
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/outbound/*"
    ]
  }

  statement {
    sid     = "ConnectorS3ListAndLocation"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.sftp_poc.arn
    ]
  }

  statement {
    sid     = "ConnectorS3KmsAccess"
    effect  = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [local.s3_kms_key_arn]
  }

  # Transfer connector lee credenciales del secreto (Username/Password/PrivateKey)
  statement {
    sid     = "ConnectorSecretsManagerRead"
    effect  = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      aws_secretsmanager_secret.sftp_connector_creds.arn
    ]
  }

  # Necesario para descifrar el secreto cuando usa el KMS gestionado por AWS
  statement {
    sid     = "ConnectorSecretsKmsDecrypt"
    effect  = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [local.secrets_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "transfer_connector_role_policy" {
  name   = "${var.project_name}-transfer-connector-policy-${var.environment}"
  role   = aws_iam_role.transfer_connector_role.id
  policy = data.aws_iam_policy_document.transfer_connector_policy.json
}

#
# Lambda inbound processor (Fase 1)
#
resource "aws_iam_role" "lambda_inbound_role" {
  name = "${var.project_name}-lambda-inbound-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_inbound_policy" {
  statement {
    sid     = "InboundRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/inbound/*"
    ]
  }

  statement {
    sid     = "OutboundWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/outbound/*"
    ]
  }

  statement {
    sid     = "LambdaS3KmsAccess"
    effect  = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [local.s3_kms_key_arn]
  }

  statement {
    sid     = "CloudWatchLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.log_resource_arn]
  }
}

resource "aws_iam_role_policy" "lambda_inbound_role_policy" {
  name   = "${var.project_name}-lambda-inbound-policy-${var.environment}"
  role   = aws_iam_role.lambda_inbound_role.id
  policy = data.aws_iam_policy_document.lambda_inbound_policy.json
}

#
# Lambda outbound sender (Fase 1)
#
resource "aws_iam_role" "lambda_outbound_role" {
  name = "${var.project_name}-lambda-outbound-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_outbound_policy" {
  statement {
    sid     = "OutboundRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.sftp_poc.arn}/outbound/*"
    ]
  }

  statement {
    sid     = "StartTransfer"
    effect  = "Allow"
    actions = ["transfer:StartFileTransfer"]
    resources = [
      aws_transfer_connector.sftp_outbound.arn
    ]
  }

  statement {
    sid     = "LambdaOutboundS3KmsAccess"
    effect  = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = [local.s3_kms_key_arn]
  }

  statement {
    sid     = "CloudWatchLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.log_resource_arn]
  }
}

resource "aws_iam_role_policy" "lambda_outbound_role_policy" {
  name   = "${var.project_name}-lambda-outbound-policy-${var.environment}"
  role   = aws_iam_role.lambda_outbound_role.id
  policy = data.aws_iam_policy_document.lambda_outbound_policy.json
}

