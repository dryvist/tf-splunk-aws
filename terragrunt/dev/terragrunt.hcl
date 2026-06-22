# Dev environment configuration
include "root" {
  path = find_in_parent_folders()
}

locals {
  network_public_ip = get_env("NETWORK_PUBLIC_IP_ADDRESS", "")
  allowed_cidrs     = local.network_public_ip != "" ? ["${local.network_public_ip}/32"] : []
  splunk_password   = get_env("SPLUNK_PASSWORD", "")
}

inputs = {
  environment          = "dev"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-2a", "us-east-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

  # Instance sizing
  nat_instance_type       = "t4g.nano"
  splunk_instance_type    = "t3a.small"
  splunk_root_volume_size = 20
  splunk_data_volume_size = 50

  # Optional: Add your key pair name for SSH access
  # key_pair_name = "your-key-pair-name"

  # SSH access: set to specific CIDRs to enable, empty list disables SSH entirely
  ssh_allowed_cidrs = []

  # Public access: place Splunk in public subnet with public IP
  splunk_public_access = true

  # Cribl Stream + Edge
  enable_cribl             = true
  management_allowed_cidrs = local.allowed_cidrs
  cribl_allowed_cidrs      = local.allowed_cidrs

  # CIDRs from Doppler NETWORK_PUBLIC_IP_ADDRESS
  # Never commit real IPs — empty default disables external access if env var unset
  web_allowed_cidrs = local.allowed_cidrs
  hec_allowed_cidrs = local.allowed_cidrs

  # Auto-lifecycle: start Splunk every 4h for 60min (~$9/mo vs ~$18/mo always-on)
  enable_auto_lifecycle = true

  # Splunk admin password: uses Doppler SPLUNK_PASSWORD if set, otherwise auto-generates
  splunk_admin_password = local.splunk_password != "" ? local.splunk_password : null
}
