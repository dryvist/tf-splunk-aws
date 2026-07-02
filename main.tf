# Root module — cost-optimized Splunk / Cribl environment on AWS.
#
# Wires together the child modules under modules/:
#   network   VPC, subnets, route tables
#   security  Security groups, IAM roles/profiles, SSM password parameter
#   compute   NAT instance (shared egress path for private subnets)
#   splunk    Splunk Enterprise instance + EBS data volume (optional)
#   cribl     Cribl Stream (Linux) + Cribl Edge (Windows) instances (optional)
#   lifecycle Auto-stop guardrails (uptime sweep + optional fixed schedule)
#   summon    GitHub Actions OIDC role for credential-less start/stop
#
# Splunk and Cribl are independently optional (enable_splunk / enable_cribl);
# the network, NAT, and guardrail layers are shared infrastructure.

# Credentials are generated per environment when not supplied, so a fresh
# deployment needs no secret inputs. All generated secrets are destroyed with
# the environment.
resource "random_password" "splunk_admin" {
  count = var.enable_splunk ? 1 : 0

  length  = var.generated_password_length
  special = true
}

# Windows local Administrator password for the Cribl Edge instance. The
# character constraints satisfy Windows password complexity requirements.
resource "random_password" "windows_admin" {
  count = var.enable_cribl ? 1 : 0

  length           = var.generated_password_length
  special          = true
  override_special = "!@#$%&*"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# A generated SSH key pair is shared by all instances unless the caller
# supplies key_pair_name. SSM Session Manager remains the primary shell
# access path; SSH is disabled unless ssh_allowed_cidrs is non-empty.
resource "tls_private_key" "access" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "${var.environment}-generated-key"
  public_key = tls_private_key.access.public_key_openssh
}

# Used to derive default availability zones for the configured region.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  effective_splunk_password = var.enable_splunk ? (
    var.splunk_admin_password != null && var.splunk_admin_password != "" ? var.splunk_admin_password : random_password.splunk_admin[0].result
  ) : null
  effective_key_pair_name = coalesce(var.key_pair_name, aws_key_pair.generated.key_name)

  # Default to the first two AZs in the region unless explicitly overridden.
  availability_zones = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  # admin_ip_cidrs is a convenience: one list (typically the operators' egress
  # IPs) granted access to every operator-facing surface. It merges into the
  # per-surface allowlists, which remain available for finer-grained control.
  web_allowed_cidrs        = distinct(concat(var.web_allowed_cidrs, var.admin_ip_cidrs))
  hec_allowed_cidrs        = distinct(concat(var.hec_allowed_cidrs, var.admin_ip_cidrs))
  management_allowed_cidrs = distinct(concat(var.management_allowed_cidrs, var.admin_ip_cidrs))
  cribl_allowed_cidrs      = distinct(concat(var.cribl_allowed_cidrs, var.admin_ip_cidrs))
}

# --- AMI selection ------------------------------------------------------------
# Each lookup can be bypassed with an explicit *_ami_id variable, e.g. to pin
# images for change control or to use hardened corporate AMIs.

# ARM64 Amazon Linux 2 for the NAT instance (Graviton is the cheapest class
# that can push NAT traffic for this workload).
data "aws_ami" "amazon_linux_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# x86_64 Amazon Linux 2 for Splunk and Cribl Stream — Splunk Enterprise has no
# public ARM64 release, so these instances must stay on x86.
data "aws_ami" "amazon_linux_x86" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Windows Server 2022 for Cribl Edge (exercises the Windows collection path).
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  nat_ami_id          = coalesce(var.nat_ami_id, data.aws_ami.amazon_linux_arm.id)
  splunk_ami_id       = coalesce(var.splunk_ami_id, data.aws_ami.amazon_linux_x86.id)
  cribl_stream_ami_id = coalesce(var.cribl_stream_ami_id, data.aws_ami.amazon_linux_x86.id)
  cribl_edge_ami_id   = coalesce(var.cribl_edge_ami_id, data.aws_ami.windows_2022.id)
}

# --- Modules ------------------------------------------------------------------

module "network" {
  source = "./modules/network"

  environment          = var.environment
  project_tag          = var.project_tag
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  environment              = var.environment
  project_tag              = var.project_tag
  vpc_id                   = module.network.vpc_id
  vpc_cidr_blocks          = [module.network.vpc_cidr_block]
  private_subnet_cidrs     = var.private_subnet_cidrs
  enable_splunk            = var.enable_splunk
  enable_cribl             = var.enable_cribl
  splunk_admin_password    = local.effective_splunk_password
  ssh_allowed_cidrs        = var.ssh_allowed_cidrs
  hec_allowed_cidrs        = local.hec_allowed_cidrs
  web_allowed_cidrs        = local.web_allowed_cidrs
  management_allowed_cidrs = local.management_allowed_cidrs
  cribl_allowed_cidrs      = local.cribl_allowed_cidrs
  allow_all_ips            = var.allow_all_ips
  splunk_web_port          = var.splunk_web_port
  splunk_hec_port          = var.splunk_hec_port
  splunk_management_port   = var.splunk_management_port
  splunk_s2s_port          = var.splunk_s2s_port
  cribl_web_port           = var.cribl_web_port
  cribl_data_port          = var.cribl_data_port
}

# NAT instance: the shared egress path for private subnets. Deployed
# regardless of which workloads are enabled so private instances can reach
# package repositories and AWS APIs.
module "compute" {
  source = "./modules/compute"

  environment           = var.environment
  project_tag           = var.project_tag
  nat_instance_type     = var.nat_instance_type
  key_pair_name         = local.effective_key_pair_name
  nat_security_group_id = module.security.nat_security_group_id
  public_subnet_ids     = module.network.public_subnet_ids
  ami_id                = local.nat_ami_id
}

module "splunk" {
  source = "./modules/splunk"

  enable_splunk            = var.enable_splunk
  environment              = var.environment
  project_tag              = var.project_tag
  splunk_instance_type     = var.splunk_instance_type
  splunk_root_volume_size  = var.splunk_root_volume_size
  splunk_data_volume_size  = var.splunk_data_volume_size
  splunk_password_ssm_name = module.security.splunk_password_ssm_name
  key_pair_name            = local.effective_key_pair_name
  splunk_security_group_ids = var.enable_splunk ? concat(
    [module.security.splunk_security_group_id],
    var.enable_cribl ? [module.security.internal_security_group_id] : []
  ) : []
  subnet_ids                   = var.splunk_public_access ? module.network.public_subnet_ids : module.network.private_subnet_ids
  associate_public_ip_address  = var.splunk_public_access
  splunk_instance_profile_name = module.security.splunk_instance_profile_name
  ami_id                       = local.splunk_ami_id
  splunk_version               = var.splunk_version
  splunk_build                 = var.splunk_build
  splunk_download_base_url     = var.splunk_download_base_url
  splunk_web_port              = var.splunk_web_port
}

module "cribl" {
  source = "./modules/cribl"

  enable_cribl                = var.enable_cribl
  environment                 = var.environment
  project_tag                 = var.project_tag
  cribl_stream_instance_type  = var.cribl_stream_instance_type
  cribl_edge_instance_type    = var.cribl_edge_instance_type
  key_pair_name               = local.effective_key_pair_name
  windows_admin_password      = var.enable_cribl ? random_password.windows_admin[0].result : null
  security_group_ids          = var.enable_cribl ? [module.security.cribl_security_group_id, module.security.internal_security_group_id] : []
  subnet_ids                  = var.splunk_public_access ? module.network.public_subnet_ids : module.network.private_subnet_ids
  associate_public_ip_address = var.splunk_public_access
  instance_profile_name       = var.enable_cribl ? module.security.cribl_instance_profile_name : null
  linux_ami_id                = local.cribl_stream_ami_id
  windows_ami_id              = local.cribl_edge_ami_id
  cribl_version               = var.cribl_version
  cribl_build                 = var.cribl_build
  cribl_download_base_url     = var.cribl_download_base_url
  cribl_web_port              = var.cribl_web_port
}

# Cost guardrails: an hourly uptime sweep stops any Project-tagged instance
# that has been running longer than max_runtime_hours, and an optional fixed
# schedule can additionally stop the whole stack at a set time.
module "lifecycle" {
  source = "./modules/lifecycle"

  environment              = var.environment
  project_tag              = var.project_tag
  enable_auto_stop         = var.enable_auto_stop
  max_runtime_hours        = var.max_runtime_hours
  enable_scheduled_stop    = var.enable_scheduled_stop
  stop_schedule_expression = var.stop_schedule_expression
}

# GitHub Actions OIDC role so authorized repository users can start/stop the
# environment ("summon") with zero AWS credentials of their own.
module "summon" {
  source = "./modules/summon"

  enable_github_summon     = var.enable_github_summon
  environment              = var.environment
  project_tag              = var.project_tag
  github_repository        = var.github_repository
  github_oidc_provider_arn = var.github_oidc_provider_arn
}

# Plan-time guard: when the criblio config layer is enabled, both the
# on-prem leader URL and bearer token must be supplied. Otherwise the
# provider and commit-deploy step both fail much later, at apply.
check "criblio_onprem_credentials_when_enabled" {
  assert {
    condition = !var.enable_criblio_config || (
      var.cribl_onprem_server_url != "" && var.cribl_onprem_bearer_token != ""
    )
    error_message = "enable_criblio_config = true requires cribl_onprem_server_url and cribl_onprem_bearer_token."
  }
}

# Declarative Cribl object management (pipelines, routes, destinations) via
# the criblio provider. Sits on top of module.cribl; disabled by default.
module "cribl_config" {
  source = "./modules/cribl-config"

  enable_criblio_config = var.enable_criblio_config
  environment           = var.environment

  providers = {
    criblio.onprem = criblio.onprem
    criblio.cloud  = criblio.cloud
  }
}

# Wire the NAT instance into the private route table so private-subnet
# instances reach the internet through it.
resource "aws_route" "private_nat" {
  route_table_id         = module.network.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.compute.nat_primary_network_interface_id
}
