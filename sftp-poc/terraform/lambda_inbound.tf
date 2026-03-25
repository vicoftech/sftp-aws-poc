resource "aws_lambda_function" "inbound_processor" {
  function_name    = "${var.project_name}-inbound-processor"
  filename         = data.archive_file.inbound_phase1.output_path
  source_code_hash = data.archive_file.inbound_phase1.output_base64sha256
  handler          = "handler_phase1.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_inbound_role.arn
  timeout          = 60

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.sftp_poc.bucket
      PHASE       = "1"
    }
  }
}

data "archive_file" "inbound_phase1" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/inbound/handler_phase1.py"
  output_path = "${path.module}/.terraform/tmp/inbound_phase1.zip"
}

# Permiso para que S3 invoque la Lambda
resource "aws_lambda_permission" "allow_s3_inbound" {
  statement_id  = "AllowS3InvokeInbound"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inbound_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sftp_poc.arn
}

resource "aws_lambda_function" "outbound_sender" {
  function_name    = "${var.project_name}-outbound-sender"
  filename         = data.archive_file.outbound_sender.output_path
  source_code_hash = data.archive_file.outbound_sender.output_base64sha256
  handler          = "handler_outbound.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_outbound_role.arn
  timeout          = 60

  environment {
    variables = {
      BUCKET_NAME  = aws_s3_bucket.sftp_poc.bucket
      CONNECTOR_ID = aws_transfer_connector.sftp_outbound.connector_id
      REMOTE_PATH  = "/upload"
    }
  }
}

data "archive_file" "outbound_sender" {
  type        = "zip"
  source_file = "${path.module}/../lambdas/outbound/handler_outbound.py"
  output_path = "${path.module}/.terraform/tmp/outbound_sender.zip"
}

resource "aws_lambda_permission" "allow_s3_outbound" {
  statement_id  = "AllowS3InvokeOutbound"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.outbound_sender.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sftp_poc.arn
}

# S3 Event Notifications
resource "aws_s3_bucket_notification" "sftp_poc_notifications" {
  bucket = aws_s3_bucket.sftp_poc.id

  depends_on = [
    aws_lambda_permission.allow_s3_inbound,
    aws_lambda_permission.allow_s3_outbound
  ]

  lambda_function {
    lambda_function_arn = aws_lambda_function.inbound_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "inbound/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.outbound_sender.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "outbound/"
  }
}

