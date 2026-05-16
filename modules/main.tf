# Root Module - Splunk AWS Infrastructure
# Orchestrates modular infrastructure components for cost-optimized Splunk deployment

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    criblio = {
      source  = "criblio/criblio"
      version = "1.23.32"
    }
  }
}

# criblio provider — two aliases:
#   onprem: bearer_auth against the Stream leader EC2 instance
#   cloud : OAuth2 client credentials against Cribl.Cloud
# Both aliases fall back to provider env vars (CRIBL_*) when the corresponding
# variable is empty, so terragrunt callers can choose either pattern.
provider "criblio" {
  alias = "onprem"

  server_url  = var.cribl_onprem_server_url != "" ? var.cribl_onprem_server_url : null
  bearer_auth = var.cribl_onprem_bearer_token != "" ? var.cribl_onprem_bearer_token : null
}

provider "criblio" {
  alias = "cloud"

  client_id       = var.cribl_cloud_client_id != "" ? var.cribl_cloud_client_id : null
  client_secret   = var.cribl_cloud_client_secret != "" ? var.cribl_cloud_client_secret : null
  organization_id = var.cribl_cloud_organization_id != "" ? var.cribl_cloud_organization_id : null
  workspace_id    = var.cribl_cloud_workspace_id != "" ? var.cribl_cloud_workspace_id : null
  cloud_domain    = var.cribl_cloud_domain
}

# AWS account identity - used for unique S3 bucket naming
data "aws_caller_identity" "current" {}

# Auto-generated credentials for ephemeral dev/DR environments
# All secrets are generated per-build and destroyed with the environment
resource "random_password" "splunk_admin" {
  length  = 24
  special = true
}

resource "random_password" "windows_admin" {
  length           = 24
  special          = true
  override_special = "!@#$%&*"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "tls_private_key" "access" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "${var.environment}-generated-key"
  public_key = tls_private_key.access.public_key_openssh
}

locals {
  effective_splunk_password = var.splunk_admin_password != null && var.splunk_admin_password != "" ? var.splunk_admin_password : random_password.splunk_admin.result
  effective_key_pair_name   = coalesce(var.key_pair_name, aws_key_pair.generated.key_name)
}

# ARM64 AMI for NAT instance (t4g.nano — Graviton)
data "aws_ami" "amazon_linux" {
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

# x86_64 AMI for Splunk instance — Splunk Enterprise has no public ARM64 release
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

# Windows Server 2022 AMI for Cribl Edge
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

# SmartStore S3 Bucket - remote storage for Splunk warm/cold index buckets
# Created at root level to break circular dependency: security needs ARN for IAM, splunk needs name for config
resource "aws_s3_bucket" "smartstore" {
  bucket = "${var.environment}-splunk-smartstore-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
    Project     = "splunk-aws"
    ManagedBy   = "terraform"
    Name        = "${var.environment}-splunk-smartstore"
  }
}

resource "aws_s3_bucket_versioning" "smartstore" {
  bucket = aws_s3_bucket.smartstore.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "smartstore" {
  bucket = aws_s3_bucket.smartstore.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "smartstore" {
  bucket = aws_s3_bucket.smartstore.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "smartstore" {
  bucket = aws_s3_bucket.smartstore.id

  rule {
    id     = "smartstore-tiering"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Network Module
module "network" {
  source = "./network"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Security Module
module "security" {
  source = "./security"

  environment              = var.environment
  vpc_id                   = module.network.vpc_id
  vpc_cidr_blocks          = [module.network.vpc_cidr_block]
  private_subnet_cidrs     = var.private_subnet_cidrs
  splunk_admin_password    = local.effective_splunk_password
  ssh_allowed_cidrs        = var.ssh_allowed_cidrs
  hec_allowed_cidrs        = var.hec_allowed_cidrs
  web_allowed_cidrs        = var.web_allowed_cidrs
  allow_all_ips            = var.allow_all_ips
  smartstore_bucket_arn    = aws_s3_bucket.smartstore.arn
  enable_cribl             = var.enable_cribl
  management_allowed_cidrs = var.management_allowed_cidrs
  cribl_allowed_cidrs      = var.cribl_allowed_cidrs
}

# Compute Module (NAT Instance)
module "compute" {
  source = "./compute"

  environment           = var.environment
  nat_instance_type     = var.nat_instance_type
  key_pair_name         = local.effective_key_pair_name
  nat_security_group_id = module.security.nat_security_group_id
  public_subnet_ids     = module.network.public_subnet_ids
  ami_id                = data.aws_ami.amazon_linux.id
}

# Splunk Module
module "splunk" {
  source = "./splunk"

  environment              = var.environment
  splunk_instance_type     = var.splunk_instance_type
  splunk_root_volume_size  = var.splunk_root_volume_size
  splunk_data_volume_size  = var.splunk_data_volume_size
  splunk_password_ssm_name = module.security.splunk_password_ssm_name
  key_pair_name            = local.effective_key_pair_name
  splunk_security_group_ids = concat(
    [module.security.splunk_security_group_id],
    var.enable_cribl ? [module.security.internal_security_group_id] : []
  )
  subnet_ids                   = var.splunk_public_access ? module.network.public_subnet_ids : module.network.private_subnet_ids
  associate_public_ip_address  = var.splunk_public_access
  splunk_instance_profile_name = module.security.splunk_instance_profile_name
  ami_id                       = data.aws_ami.amazon_linux_x86.id
  splunk_version               = var.splunk_version
  splunk_build                 = var.splunk_build
  smartstore_bucket_name       = aws_s3_bucket.smartstore.bucket
  enable_auto_lifecycle        = var.enable_auto_lifecycle
  auto_shutdown_minutes        = var.auto_shutdown_minutes
  lifecycle_interval_hours     = var.lifecycle_interval_hours
}

# Cribl Module (Stream + Edge)
module "cribl" {
  source = "./cribl"

  environment                 = var.environment
  enable_cribl                = var.enable_cribl
  cribl_stream_instance_type  = var.cribl_stream_instance_type
  cribl_edge_instance_type    = var.cribl_edge_instance_type
  key_pair_name               = local.effective_key_pair_name
  windows_admin_password      = random_password.windows_admin.result
  security_group_ids          = var.enable_cribl ? [module.security.cribl_security_group_id, module.security.internal_security_group_id] : []
  subnet_ids                  = var.splunk_public_access ? module.network.public_subnet_ids : module.network.private_subnet_ids
  associate_public_ip_address = var.splunk_public_access
  instance_profile_name       = var.enable_cribl ? module.security.cribl_instance_profile_name : null
  linux_ami_id                = data.aws_ami.amazon_linux_x86.id
  windows_ami_id              = data.aws_ami.windows_2022.id
}

# Plan-time guard: when the criblio config layer is enabled, both the
# on-prem leader URL and bearer token must be supplied. Otherwise the
# provider and commit-deploy step both fail much later, at apply.
check "criblio_onprem_credentials_when_enabled" {
  assert {
    condition = !var.enable_criblio_config || (
      var.cribl_onprem_server_url != "" && var.cribl_onprem_bearer_token != ""
    )
    error_message = "enable_criblio_config = true requires cribl_onprem_server_url and cribl_onprem_bearer_token (sourced from SSM via terragrunt inputs)."
  }
}

# Cribl Config Module — declarative Cribl object management via criblio provider.
# Sits on top of module.cribl. Disabled by default; gated by var.enable_criblio_config.
module "cribl_config" {
  source = "./cribl-config"

  enable_criblio_config = var.enable_criblio_config
  environment           = var.environment

  providers = {
    criblio.onprem = criblio.onprem
    criblio.cloud  = criblio.cloud
  }
}

# Route private subnet traffic through NAT instance
# This wires the compute module's NAT instance to the network module's private route table
resource "aws_route" "private_nat" {
  route_table_id         = module.network.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.compute.nat_primary_network_interface_id

}
