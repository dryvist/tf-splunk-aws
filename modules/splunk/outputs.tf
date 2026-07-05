# Splunk module outputs. All are null when enable_splunk = false.

output "splunk_instance_id" {
  description = "ID of the Splunk instance (null when disabled)"
  value       = try(aws_instance.splunk[0].id, null)
}

output "splunk_instance_private_ip" {
  description = "Private IP address of the Splunk instance (null when disabled)"
  value       = try(aws_instance.splunk[0].private_ip, null)
}

output "splunk_instance_public_ip" {
  description = "Public IP address of the Splunk instance (null when disabled or in a private subnet)"
  value       = try(aws_instance.splunk[0].public_ip, null)
}

output "splunk_web_url" {
  description = "URL for Splunk Web (uses public IP when available, otherwise private; null when disabled)"
  value       = try("http://${coalesce(aws_instance.splunk[0].public_ip, aws_instance.splunk[0].private_ip)}:${var.splunk_web_port}", null)
}

output "splunk_cloudwatch_log_group" {
  description = "CloudWatch log group for the Splunk instance (null when disabled)"
  value       = try(aws_cloudwatch_log_group.splunk[0].name, null)
}

output "splunk_app_log_group" {
  description = "CloudWatch log group for Splunk application logs (null when disabled)"
  value       = try(aws_cloudwatch_log_group.splunk_app[0].name, null)
}
