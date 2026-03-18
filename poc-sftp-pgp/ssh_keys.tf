data "local_file" "sftp_user_private" {
  # Private key generated manually at C:\Temp\external_client
  filename = "C:/Temp/external_client"
}

data "local_file" "sftp_user_public" {
  # Public key generated manually at C:\Temp\external_client.pub
  filename = "C:/Temp/external_client.pub"
}

