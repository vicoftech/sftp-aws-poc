data "archive_file" "lambda_inbound" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/inbound"
  output_path = "${path.module}/.terraform/lambda_inbound.zip"
}

data "archive_file" "lambda_outbound" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/outbound"
  output_path = "${path.module}/.terraform/lambda_outbound.zip"
}

resource "aws_cloudwatch_log_group" "inbound" {
  name              = "/aws/lambda/${local.lambda_inbound_name}"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "outbound" {
  name              = "/aws/lambda/${local.lambda_outbound_name}"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_lambda_function" "inbound" {
  function_name = local.lambda_inbound_name
  role          = aws_iam_role.lambda_inbound.arn
  runtime       = "python3.12"
  handler       = "handler.handler"

  filename         = data.archive_file.lambda_inbound.output_path
  source_code_hash = data.archive_file.lambda_inbound.output_base64sha256

  timeout     = 300
  memory_size = 512

  ephemeral_storage {
    size = 1024
  }

  environment {
    variables = {
      KMS_ASYM_KEY_SECRET_ARN = aws_secretsmanager_secret.kms_asymmetric_key.arn
      S3_BUCKET_NAME          = aws_s3_bucket.poc.id
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "outbound" {
  function_name = local.lambda_outbound_name
  role          = aws_iam_role.lambda_outbound.arn
  runtime       = "python3.12"
  handler       = "handler.handler"

  filename         = data.archive_file.lambda_outbound.output_path
  source_code_hash = data.archive_file.lambda_outbound.output_base64sha256

  timeout     = 300
  memory_size = 512

  ephemeral_storage {
    size = 1024
  }

  environment {
    variables = {
      KMS_ASYM_KEY_SECRET_ARN = aws_secretsmanager_secret.kms_asymmetric_key.arn
      S3_BUCKET_NAME          = aws_s3_bucket.poc.id
    }
  }

  depends_on = [
    time_sleep.wait_transfer_ready
  ]

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_s3_inbound" {
  statement_id  = "AllowExecutionFromS3Inbound"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inbound.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.poc.arn
}

resource "aws_lambda_permission" "allow_s3_outbound" {
  statement_id  = "AllowExecutionFromS3Outbound"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.outbound.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.poc.arn
}

