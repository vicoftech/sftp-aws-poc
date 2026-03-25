output "transfer_server_endpoint" {
  description = "Endpoint del Transfer Family Server (para conectar cliente SFTP)"
  value       = aws_transfer_server.sftp.endpoint
}

output "transfer_server_id" {
  description = "ID del Transfer Family Server"
  value       = aws_transfer_server.sftp.id
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.sftp_poc.bucket
}

output "connector_id" {
  description = "ID del Transfer Family Connector"
  value       = aws_transfer_connector.sftp_outbound.connector_id
}

