# Root module outputs.
# Workload-specific outputs are null when the corresponding toggle
# (enable_splunk / enable_cribl) is off.

# --- Network ------------------------------------------------------------------

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

# --- Security groups ----------------------------------------------------------

output "nat_security_group_id" {
  description = "ID of the NAT instance security group"
  value       = module.security.nat_security_group_id
}

output "splunk_security_group_id" {
  description = "ID of the Splunk security group (null when Splunk disabled)"
  value       = module.security.splunk_security_group_id
}

output "internal_security_group_id" {
  description = "ID of the internal cluster security group (null when Cribl disabled)"
  value       = module.security.internal_security_group_id
}

output "cribl_security_group_id" {
  description = "ID of the Cribl security group (null when Cribl disabled)"
  value       = module.security.cribl_security_group_id
}

# --- NAT instance ---------------------------------------------------------------

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

# --- Splunk ---------------------------------------------------------------------

output "splunk_instance_id" {
  description = "ID of the Splunk instance (null when disabled)"
  value       = module.splunk.splunk_instance_id
}

output "splunk_instance_private_ip" {
  description = "Private IP address of the Splunk instance (null when disabled)"
  value       = module.splunk.splunk_instance_private_ip
}

output "splunk_instance_public_ip" {
  description = "Public IP address of the Splunk instance (null when disabled or in a private subnet)"
  value       = module.splunk.splunk_instance_public_ip
}

output "splunk_web_url" {
  description = "URL for Splunk Web (uses public IP when available; null when disabled)"
  value       = module.splunk.splunk_web_url
}

# --- Cribl ----------------------------------------------------------------------

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

# --- Cost estimate --------------------------------------------------------------
# On-demand us-east-2 pricing, computed from the enabled components. EBS is
# billed while instances are stopped; compute is not, which is why the
# auto-stop guardrail dominates the real monthly spend.

locals {
  # Monthly on-demand estimates (USD, 730 hrs) per component.
  cost_components = merge(
    {
      nat     = { compute = 3.07, storage = 0.64 }
      network = { compute = 0, storage = 0 }
    },
    var.enable_splunk ? {
      splunk = { compute = 13.72, storage = (var.splunk_root_volume_size + var.splunk_data_volume_size) * 0.08 }
    } : {},
    var.enable_cribl ? {
      cribl_stream = { compute = 13.72, storage = 2.40 }
      cribl_edge   = { compute = 54.31, storage = 2.40 }
    } : {}
  )

  monthly_compute = sum([for c in local.cost_components : c.compute])
  monthly_storage = sum([for c in local.cost_components : c.storage])
  monthly_total   = local.monthly_compute + local.monthly_storage
}

output "estimated_cost" {
  description = "Estimated monthly cost (USD, on-demand us-east-2) for the enabled components"
  value = {
    always_on_monthly = format("$%.2f", local.monthly_total)
    stopped_monthly   = format("$%.2f (EBS only — what you pay when the auto-stop guardrail has stopped the stack)", local.monthly_storage)
    daily_running     = format("$%.2f", local.monthly_total / 30)
    components        = { for k, c in local.cost_components : k => format("$%.2f compute + $%.2f storage", c.compute, c.storage) }
  }
}

# --- Connection summary ---------------------------------------------------------

output "connection_info" {
  description = "Connection information for the deployed services"
  value = merge(
    {
      vpc_id       = module.network.vpc_id
      nat_instance = module.compute.nat_instance_public_ip
    },
    var.enable_splunk ? {
      splunk_web_url   = module.splunk.splunk_web_url
      splunk_public_ip = module.splunk.splunk_instance_public_ip
    } : {},
    var.enable_cribl ? {
      cribl_stream_web_url = module.cribl.cribl_stream_web_url
      cribl_edge_ip        = module.cribl.cribl_edge_private_ip
    } : {}
  )
}

# All access credentials — ephemeral, generated per deployment and destroyed
# with the environment. nonsensitive() is deliberate: these are disposable
# environment credentials surfaced for the operator who just deployed them.
# Retrieve with: tofu output access_credentials
output "access_credentials" {
  description = "IPs, usernames, passwords, and SSH keys for the current deployment"
  value = {
    ssh_private_key = nonsensitive(tls_private_key.access.private_key_openssh)
    ssh_key_name    = aws_key_pair.generated.key_name

    splunk = var.enable_splunk ? {
      web_url   = module.splunk.splunk_web_url
      public_ip = module.splunk.splunk_instance_public_ip
      username  = "admin"
      password  = nonsensitive(local.effective_splunk_password)
      ssh       = module.splunk.splunk_instance_public_ip != null ? "ssh -i key.pem ec2-user@${module.splunk.splunk_instance_public_ip}" : "Use SSM Session Manager"
    } : null

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
      password  = nonsensitive(random_password.windows_admin[0].result)
      rdp       = module.cribl.cribl_edge_public_ip != null ? "mstsc /v:${module.cribl.cribl_edge_public_ip}" : "Use SSM Session Manager"
    } : null
  }
}
