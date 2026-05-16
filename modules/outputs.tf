# Root Module Outputs
# Aggregates outputs from all infrastructure modules

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.network.private_subnet_ids
}

# Security Outputs
output "nat_security_group_id" {
  description = "ID of the NAT instance security group"
  value       = module.security.nat_security_group_id
}

output "splunk_security_group_id" {
  description = "ID of the Splunk security group"
  value       = module.security.splunk_security_group_id
}

# Compute Outputs
output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = module.compute.nat_instance_id
}

output "nat_instance_public_ip" {
  description = "Public IP address of the NAT instance"
  value       = module.compute.nat_instance_public_ip
}

output "nat_instance_private_ip" {
  description = "Private IP address of the NAT instance"
  value       = module.compute.nat_instance_private_ip
}

# Splunk Outputs
output "splunk_instance_id" {
  description = "ID of the Splunk instance"
  value       = module.splunk.splunk_instance_id
}

output "splunk_instance_private_ip" {
  description = "Private IP address of the Splunk instance"
  value       = module.splunk.splunk_instance_private_ip
}

output "splunk_instance_public_ip" {
  description = "Public IP address of the Splunk instance (null when in private subnet)"
  value       = module.splunk.splunk_instance_public_ip
}

output "splunk_web_url" {
  description = "URL for Splunk Web interface (uses public IP when available)"
  value       = module.splunk.splunk_web_url
}

# Cribl Outputs
output "cribl_stream_instance_id" {
  description = "ID of the Cribl Stream instance (null when disabled)"
  value       = module.cribl.cribl_stream_instance_id
}

output "cribl_stream_private_ip" {
  description = "Private IP of the Cribl Stream instance (null when disabled)"
  value       = module.cribl.cribl_stream_private_ip
}

output "cribl_stream_public_ip" {
  description = "Public IP of the Cribl Stream instance (null when disabled)"
  value       = module.cribl.cribl_stream_public_ip
}

output "cribl_stream_web_url" {
  description = "URL for Cribl Stream Web UI (null when disabled)"
  value       = module.cribl.cribl_stream_web_url
}

output "cribl_edge_instance_id" {
  description = "ID of the Cribl Edge instance (null when disabled)"
  value       = module.cribl.cribl_edge_instance_id
}

output "cribl_edge_private_ip" {
  description = "Private IP of the Cribl Edge instance (null when disabled)"
  value       = module.cribl.cribl_edge_private_ip
}

output "cribl_edge_public_ip" {
  description = "Public IP of the Cribl Edge instance (null when disabled)"
  value       = module.cribl.cribl_edge_public_ip
}

# Security Group Outputs (Cribl)
output "internal_security_group_id" {
  description = "ID of the internal cluster security group (null when Cribl disabled)"
  value       = module.security.internal_security_group_id
}

output "cribl_security_group_id" {
  description = "ID of the Cribl security group (null when Cribl disabled)"
  value       = module.security.cribl_security_group_id
}

# Cost Estimation
output "estimated_cost" {
  description = "Estimated daily and monthly cost in USD (always-on vs auto-lifecycle)"
  value = var.enable_cribl ? {
    daily = {
      always_on      = "$2.57/day"
      auto_lifecycle = "$2.26/day"
      breakdown      = "NAT: $0.08, Splunk: $0.41 (always-on) / $0.10 (lifecycle), Stream: $0.46, Edge/Win: $1.41, EBS: $0.21"
    }
    monthly = {
      always_on      = "$77/mo"
      auto_lifecycle = "$68/mo"
      breakdown      = "NAT: $2.52, Splunk: $12.18 (always-on) / $3.05 (lifecycle), Stream: $13.74, Edge/Win: $42.34, EBS: $6.17"
    }
    } : {
    daily = {
      always_on      = "$0.59/day"
      auto_lifecycle = "$0.28/day"
      breakdown      = "NAT: $0.08, Splunk: $0.41 (always-on) / $0.10 (lifecycle), EBS: $0.10"
    }
    monthly = {
      always_on      = "$17.67/mo"
      auto_lifecycle = "$8.54/mo"
      breakdown      = "NAT: $2.52, Splunk: $12.18 (always-on) / $3.05 (lifecycle), EBS: $2.97"
    }
  }
}

# Access Information
output "connection_info" {
  description = "Connection information for accessing the infrastructure"
  value = merge(
    {
      splunk_web_url   = module.splunk.splunk_web_url
      splunk_public_ip = module.splunk.splunk_instance_public_ip
      vpc_id           = module.network.vpc_id
      nat_instance     = module.compute.nat_instance_public_ip
    },
    var.enable_cribl ? {
      cribl_stream_web_url = module.cribl.cribl_stream_web_url
      cribl_edge_ip        = module.cribl.cribl_edge_private_ip
    } : {}
  )
}

# All access credentials — ephemeral, auto-generated per-build
# Using nonsensitive() because these are disposable dev/DR credentials
# destroyed with the environment. Run `terragrunt output access_credentials` to retrieve.
output "access_credentials" {
  description = "All IPs, usernames, passwords, and SSH keys for the current deployment"
  value = {
    ssh_private_key = nonsensitive(tls_private_key.access.private_key_openssh)
    ssh_key_name    = aws_key_pair.generated.key_name

    splunk = {
      web_url   = module.splunk.splunk_web_url
      public_ip = module.splunk.splunk_instance_public_ip
      username  = "admin"
      password  = nonsensitive(local.effective_splunk_password)
      ssh       = module.splunk.splunk_instance_public_ip != null ? "ssh -i key.pem ec2-user@${module.splunk.splunk_instance_public_ip}" : "Use SSM Session Manager"
    }

    nat = {
      public_ip = module.compute.nat_instance_public_ip
      ssh       = "ssh -i key.pem ec2-user@${module.compute.nat_instance_public_ip}"
    }

    cribl_stream = var.enable_cribl ? {
      web_url   = module.cribl.cribl_stream_web_url
      public_ip = module.cribl.cribl_stream_public_ip
      username  = "admin"
      password  = "admin (change on first login)"
      ssh       = module.cribl.cribl_stream_public_ip != null ? "ssh -i key.pem ec2-user@${module.cribl.cribl_stream_public_ip}" : "Use SSM Session Manager"
    } : null

    windows_rdp = var.enable_cribl ? {
      public_ip = module.cribl.cribl_edge_public_ip
      username  = "Administrator"
      password  = nonsensitive(random_password.windows_admin.result)
      rdp       = module.cribl.cribl_edge_public_ip != null ? "mstsc /v:${module.cribl.cribl_edge_public_ip}" : "Use SSM Session Manager"
    } : null
  }
}
