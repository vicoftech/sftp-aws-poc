resource "aws_s3_bucket" "poc" {
  bucket = local.bucket_name

  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "poc" {
  bucket = aws_s3_bucket.poc.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "poc" {
  bucket = aws_s3_bucket.poc.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "poc" {
  bucket = aws_s3_bucket.poc.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "poc" {
  bucket = aws_s3_bucket.poc.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.poc.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_object" "inbound_placeholder" {
  bucket  = aws_s3_bucket.poc.id
  key     = "inbound/.keep"
  content = ""

  tags = local.common_tags
}

resource "aws_s3_object" "outbound_placeholder" {
  bucket  = aws_s3_bucket.poc.id
  key     = "outbound/.keep"
  content = ""

  tags = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "poc" {
  bucket = aws_s3_bucket.poc.id

  rule {
    id     = "inbound-lifecycle"
    status = "Enabled"

    filter {
      prefix = "inbound/"
    }

    transition {
      days          = 1
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "outbound-lifecycle"
    status = "Enabled"

    filter {
      prefix = "outbound/"
    }

    transition {
      days          = 1
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 7
    }
  }

  # NOTE: S3 Lifecycle minimum transition is 1 day — cannot use minutes.
  # For production, consider S3 Object Lock or EventBridge for finer control.
}

resource "aws_s3_bucket_notification" "poc" {
  bucket = aws_s3_bucket.poc.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.inbound.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "inbound/"
    filter_suffix       = ".pgp"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.outbound.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "outbound/"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_inbound,
    aws_lambda_permission.allow_s3_outbound
  ]
}


