locals {
  test_file_content = <<-EOT
    POC_TEST_FILE_v1
    timestamp: ${timestamp()}
    content: HELLO_FROM_EXTERNAL_CLIENT
    checksum_word: TRANSFER_FAMILY_PGP_OK
  EOT
}

resource "local_file" "test_plain" {
  filename = "${path.module}/test_files/test_payload_plain.txt"
  content  = local.test_file_content
}

resource "null_resource" "encrypt_test_file" {
  depends_on = [
    null_resource.pgp_internal_keys,
    local_file.test_plain
  ]

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = "Stop"
      $workDir = Join-Path "${path.module}" "test_files"

      & gpg --batch --yes --trust-model always `
        --encrypt --armor `
        --recipient internal@poc.local `
        --output (Join-Path $workDir "test_payload.txt.pgp") `
        (Join-Path $workDir "test_payload_plain.txt")
    EOT
  }
}

resource "local_file" "test_outbound" {
  filename = "${path.module}/test_files/test_outbound_plain.txt"
  content  = "OUTBOUND_TEST_FILE\ncontent: HELLO_TO_EXTERNAL_CLIENT\n"
}

