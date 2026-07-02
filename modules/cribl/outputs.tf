# Cribl module outputs. All are null when enable_cribl = false.

output "cribl_stream_instance_id" {
  description = "ID of the Cribl Stream instance (null when disabled)"
  value       = try(aws_instance.cribl_stream[0].id, null)
}

output "cribl_stream_private_ip" {
  description = "Private IP of the Cribl Stream instance (null when disabled)"
  value       = try(aws_instance.cribl_stream[0].private_ip, null)
}

output "cribl_stream_public_ip" {
  description = "Public IP of the Cribl Stream instance (null when disabled or in a private subnet)"
  value       = try(aws_instance.cribl_stream[0].public_ip, null)
}

output "cribl_stream_web_url" {
  description = "URL for Cribl Stream Web UI (null when disabled)"
  value       = try("http://${coalesce(aws_instance.cribl_stream[0].public_ip, aws_instance.cribl_stream[0].private_ip)}:${var.cribl_web_port}", null)
}

output "cribl_edge_instance_id" {
  description = "ID of the Cribl Edge instance (null when disabled)"
  value       = try(aws_instance.cribl_edge[0].id, null)
}

output "cribl_edge_private_ip" {
  description = "Private IP of the Cribl Edge instance (null when disabled)"
  value       = try(aws_instance.cribl_edge[0].private_ip, null)
}

output "cribl_edge_public_ip" {
  description = "Public IP of the Cribl Edge instance (null when disabled or in a private subnet)"
  value       = try(aws_instance.cribl_edge[0].public_ip, null)
}
