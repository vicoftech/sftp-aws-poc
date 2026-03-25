resource "aws_s3_bucket" "sftp_poc" {
  bucket        = "${var.project_name}-sftp-poc-${var.environment}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "sftp_poc" {
  bucket = aws_s3_bucket.sftp_poc.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sftp_poc" {
  bucket = aws_s3_bucket.sftp_poc.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

# Bloquear acceso público
resource "aws_s3_bucket_public_access_block" "sftp_poc" {
  bucket                  = aws_s3_bucket.sftp_poc.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

