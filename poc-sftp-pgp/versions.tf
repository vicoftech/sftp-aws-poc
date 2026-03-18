terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "poc-sftp-pgp"
      Environment = "poc"
      ManagedBy   = "terraform"
      Module      = "aws-ia/transfer-family"
    }
  }
}

