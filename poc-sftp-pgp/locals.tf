resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "poc"
    ManagedBy   = "terraform"
  }

  bucket_name          = "${var.project_name}-${random_id.suffix.hex}"
  lambda_inbound_name  = "${var.project_name}-inbound-decrypt"
  lambda_outbound_name = "${var.project_name}-outbound-encrypt"
  inbound_prefix       = "inbound/"
  outbound_prefix      = "outbound/"
}

