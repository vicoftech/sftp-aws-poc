data "aws_caller_identity" "current" {}

data "aws_region" "iam" {}

resource "aws_iam_role" "transfer_family" {
  name = "poc-transfer-family-role"

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

  tags = local.common_tags
}

resource "aws_iam_policy" "transfer_family" {
  name        = "poc-transfer-family-policy"
  description = "Permissions for AWS Transfer Family to access S3 and CloudWatch Logs for POC"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.poc.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.poc.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.poc.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "transfer_family" {
  role       = aws_iam_role.transfer_family.name
  policy_arn = aws_iam_policy.transfer_family.arn
}

resource "aws_iam_role" "transfer_logging" {
  name = "poc-transfer-logging-role"

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

  tags = local.common_tags
}

resource "aws_iam_policy" "transfer_logging" {
  name        = "poc-transfer-logging-policy"
  description = "Logging policy for AWS Transfer Family POC"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "transfer_logging" {
  role       = aws_iam_role.transfer_logging.name
  policy_arn = aws_iam_policy.transfer_logging.arn
}

resource "aws_iam_role" "lambda_inbound" {
  name = "poc-lambda-inbound-role"

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

  tags = local.common_tags
}

resource "aws_iam_role" "lambda_outbound" {
  name = "poc-lambda-outbound-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_inbound_basic" {
  role       = aws_iam_role.lambda_inbound.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_outbound_basic" {
  role       = aws_iam_role.lambda_outbound.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_inbound" {
  name        = "poc-lambda-inbound-policy"
  description = "Permissions for inbound Lambda to decrypt PGP files from S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.poc.arn}/inbound/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.internal_private.arn,
          aws_secretsmanager_secret.external_public.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.poc.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.iam.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_inbound_name}*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_inbound" {
  role       = aws_iam_role.lambda_inbound.name
  policy_arn = aws_iam_policy.lambda_inbound.arn
}

resource "aws_iam_policy" "lambda_outbound" {
  name        = "poc-lambda-outbound-policy"
  description = "Permissions for outbound Lambda to encrypt PGP files and send via SFTP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.poc.arn}/outbound/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.external_public.arn,
          aws_secretsmanager_secret.sftp_user_private_key.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.poc.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.iam.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_outbound_name}*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_outbound" {
  role       = aws_iam_role.lambda_outbound.name
  policy_arn = aws_iam_policy.lambda_outbound.arn
}

