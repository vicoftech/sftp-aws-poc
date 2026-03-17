terraform {
  backend "s3" {
    bucket         = "bsj-terraform-state-315453809993"
    key            = "poc-sftp-pgp/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock-sftp-poc"
    encrypt        = true
  }
}

