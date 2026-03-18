resource "tls_private_key" "sftp_user" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "transfer_poc" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "transfer_poc" {
  private_key_pem = tls_private_key.transfer_poc.private_key_pem

  subject {
    common_name = "poc-sftp-transfer.local"
  }

  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "cert_signing",
  ]
}

resource "aws_acm_certificate" "transfer_poc" {
  private_key      = tls_private_key.transfer_poc.private_key_pem
  certificate_body = tls_self_signed_cert.transfer_poc.cert_pem
}

# External and internal PGP key generation using gpg local-exec

data "local_file" "external_public" {
  depends_on = [null_resource.pgp_external_keys]
  filename   = "${path.module}/.pgp/poc_external_public.asc"
}

data "local_file" "external_private" {
  depends_on = [null_resource.pgp_external_keys]
  filename   = "${path.module}/.pgp/poc_external_private.asc"
}

data "local_file" "internal_public" {
  depends_on = [null_resource.pgp_internal_keys]
  filename   = "${path.module}/.pgp/poc_internal_public.asc"
}

data "local_file" "internal_private" {
  depends_on = [null_resource.pgp_internal_keys]
  filename   = "${path.module}/.pgp/poc_internal_private.asc"
}

resource "null_resource" "pgp_external_keys" {
  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = "Stop"

      $workDir = Join-Path "${path.module}" ".pgp"
      New-Item -ItemType Directory -Force -Path $workDir | Out-Null

      $externalParams = @"
%echo Generating external PGP key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: SFTP External Client
Name-Email: external@poc.local
Expire-Date: 0
%no-protection
%commit
%echo done
"@

      $paramsPath = Join-Path $workDir "external_params"
      $externalParams | Out-File -FilePath $paramsPath -Encoding ascii

      & gpg --batch --gen-key $paramsPath

      & gpg --armor --export "external@poc.local" |
        Out-File -FilePath (Join-Path $workDir "poc_external_public.asc") -Encoding ascii

      & gpg --armor --export-secret-keys "external@poc.local" |
        Out-File -FilePath (Join-Path $workDir "poc_external_private.asc") -Encoding ascii
    EOT
  }
}

resource "null_resource" "pgp_internal_keys" {
  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = "Stop"

      $workDir = Join-Path "${path.module}" ".pgp"
      New-Item -ItemType Directory -Force -Path $workDir | Out-Null

      $internalParams = @"
%echo Generating internal PGP key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: AWS Transfer Internal
Name-Email: internal@poc.local
Expire-Date: 0
%no-protection
%commit
%echo done
"@

      $paramsPath = Join-Path $workDir "internal_params"
      $internalParams | Out-File -FilePath $paramsPath -Encoding ascii

      & gpg --batch --gen-key $paramsPath

      & gpg --armor --export "internal@poc.local" |
        Out-File -FilePath (Join-Path $workDir "poc_internal_public.asc") -Encoding ascii

      & gpg --armor --export-secret-keys "internal@poc.local" |
        Out-File -FilePath (Join-Path $workDir "poc_internal_private.asc") -Encoding ascii
    EOT
  }
}

