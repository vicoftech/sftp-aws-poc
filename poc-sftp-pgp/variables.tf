variable "aws_region" {
  description = "AWS region for the POC"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
  default     = "poc-sftp-pgp"
}

variable "pgp_passphrase" {
  description = "Passphrase for PGP private keys (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

