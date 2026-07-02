# Security module outputs. Splunk/Cribl outputs are null when the
# corresponding toggle is off.

output "nat_security_group_id" {
  description = "ID of the NAT instance security group"
  value       = aws_security_group.nat_instance.id
}

output "splunk_security_group_id" {
  description = "ID of the Splunk security group (null when Splunk disabled)"
  value       = try(aws_security_group.splunk[0].id, null)
}

output "splunk_instance_profile_name" {
  description = "Name of the Splunk IAM instance profile (null when Splunk disabled)"
  value       = try(aws_iam_instance_profile.splunk[0].name, null)
}

output "splunk_iam_role_arn" {
  description = "ARN of the Splunk IAM role (null when Splunk disabled)"
  value       = try(aws_iam_role.splunk_instance[0].arn, null)
}

output "splunk_password_ssm_name" {
  description = "SSM Parameter Store name of the Splunk admin password (null when Splunk disabled)"
  value       = try(aws_ssm_parameter.splunk_admin_password[0].name, null)
}

output "internal_security_group_id" {
  description = "ID of the internal cluster security group (null when Cribl disabled)"
  value       = try(aws_security_group.internal[0].id, null)
}

output "cribl_security_group_id" {
  description = "ID of the Cribl security group (null when Cribl disabled)"
  value       = try(aws_security_group.cribl[0].id, null)
}

output "cribl_instance_profile_name" {
  description = "Name of the Cribl IAM instance profile (null when Cribl disabled)"
  value       = try(aws_iam_instance_profile.cribl[0].name, null)
}
