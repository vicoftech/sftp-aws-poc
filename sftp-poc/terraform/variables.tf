variable "project_name" {
  description = "Nombre base del proyecto"
  type        = string
  default     = "workium-sftp-poc"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "sftp_username" {
  description = "Nombre del usuario SFTP en Transfer Family"
  type        = string
  default     = "sftpuser"
}

variable "sftp_user_public_key" {
  description = "Clave pública SSH del usuario SFTP (generada con scripts/generate_sftp_keys.sh)"
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDbFdReiErkU2zPEzx5khw0z87vRab+U7bJBfVmWrukP/pIINzuMwn0cbXXuqDAWLwH7lvjG6cVT0QtLr0FgIlpUUUKnthPDkbUQNVipyulKR/n7058IQg4mGpDPejtfLgLD1NRhhV/cZTD+Efs+7PbAri4W/INLQHZzyMijIue6WMvcbxG7sq+BWx3iEmoKwQKhEUytd5hWkYWA3XOlD7icoL6ytfyKms6WsGLisBIEO1tFYQgrr8dhQCCdDX5IjFrsV8Cp5TdktB/Do7ozTMSVkafoCPixLbffpgtx1UqnlAc/775Ir9us+7qdWLQPp0aqLx8IqCtdAQz7MJyAgRt/OoIbDkF7POhlXtR5fmhV+w93SKV8GtsYB/4ZHD7vT0AuavX3SMj7eZnRxsJdRMn4p82I+9wHbqMlyDAn2THxs5rg8k7oyw0rZlsHO9r+wj1SFd2T+ZaO1tnGqq46zoyL67leLyHoG/Poea1vDImqmsg+IWH+TsN+camQRrwM/TZxhK3AT2hYjKcajeGP5y6WzaxAKoIzDkYok68aUo2FAruhYZcE+PxxCPpbS8zgVhwgcU1quWuITxciZ1o32bYxordzZqei1yKeLLdxA36w5owE+14mKnIvkhBH4BkpY43c8hTkufDBMABye0t9dlJq33F+SUoDQvCuMDxQfw7/Q=="
}

