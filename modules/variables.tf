# Root Module Variables

variable "environment" {
  description = "Environment name (dev/stg/prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for instances (optional)"
  type        = string
  default     = null
}

variable "nat_instance_type" {
  description = "Instance type for NAT instance"
  type        = string
  default     = "t4g.nano"
}

variable "splunk_instance_type" {
  description = "Instance type for Splunk instance (must be x86_64 — Splunk Enterprise has no public ARM64 release)"
  type        = string
  default     = "t3a.small"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]g\\.)", var.splunk_instance_type))
    error_message = "splunk_instance_type must be x86_64. ARM/Graviton families (e.g., t4g.*, c6g.*, m6g.*, a1.*) are not supported — Splunk Enterprise has no public ARM64 release."
  }
}

variable "splunk_root_volume_size" {
  description = "Size of root volume for Splunk instance (GB)"
  type        = number
  default     = 20
}

variable "splunk_data_volume_size" {
  description = "Size of data volume for Splunk instance (GB)"
  type        = number
  default     = 50
}

variable "splunk_admin_password" {
  description = "Admin password for Splunk. If null or empty, a random 24-char password is generated per-build."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.splunk_admin_password == null || var.splunk_admin_password == "" || length(var.splunk_admin_password) >= 8
    error_message = "Splunk admin password must be at least 8 characters when provided."
  }
}

variable "splunk_version" {
  description = "Splunk Enterprise version to install"
  type        = string
  default     = "9.4.9"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.splunk_version))
    error_message = "Splunk version must be in X.Y.Z format (e.g., 9.4.9)."
  }
}

variable "splunk_build" {
  description = "Splunk Enterprise build hash for the download URL"
  type        = string
  default     = "03bb451d4e07"

  validation {
    condition     = can(regex("^[a-f0-9]{12}$", var.splunk_build))
    error_message = "Splunk build must be a 12-character hexadecimal string."
  }
}

variable "splunk_public_access" {
  description = "Place Splunk in a public subnet with a public IP. When true, Splunk gets a public IP and sits in the public subnet."
  type        = bool
  default     = false
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed access to Splunk Web (port 8000). Creates a security group rule whenever non-empty, regardless of splunk_public_access. Useful for VPN/peering access to private instances."
  type        = list(string)
  default     = []
}

variable "hec_allowed_cidrs" {
  description = "CIDR blocks allowed to send data to Splunk HEC (port 8088). Set to your on-prem/cloud source IPs."
  type        = list(string)
  default     = []
}

variable "allow_all_ips" {
  description = "Override web_allowed_cidrs and hec_allowed_cidrs to 0.0.0.0/0. Must be set via CLI (TF_VAR_allow_all_ips=true) — never committed in terragrunt config."
  type        = bool
  default     = false
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access to instances (port 22). Set to [] to disable SSH, or provide specific CIDRs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "Each ssh_allowed_cidrs entry must be a valid CIDR block, e.g. 203.0.113.0/24 or 0.0.0.0/0."
  }
}

variable "enable_cribl" {
  description = "Enable Cribl Stream and Edge instances"
  type        = bool
  default     = true
}

variable "cribl_stream_instance_type" {
  description = "Instance type for Cribl Stream (must be x86_64)"
  type        = string
  default     = "t3a.small"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]+g[a-z]*\\.)", var.cribl_stream_instance_type))
    error_message = "cribl_stream_instance_type must be x86_64. ARM/Graviton families are not supported."
  }
}

variable "cribl_edge_instance_type" {
  description = "Instance type for Cribl Edge Windows instance (must be x86_64)"
  type        = string
  default     = "t3a.medium"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]+g[a-z]*\\.)", var.cribl_edge_instance_type))
    error_message = "cribl_edge_instance_type must be x86_64. ARM/Graviton families are not supported."
  }
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks for management ports (RDP 3389, Splunk mgmt 8089) — always restricted, never affected by allow_all_ips. SSH is controlled by ssh_allowed_cidrs."
  type        = list(string)
  default     = []
}

variable "cribl_allowed_cidrs" {
  description = "CIDR blocks for Cribl ports (4200 Web/leader, 9997 data ingest) — affected by allow_all_ips"
  type        = list(string)
  default     = []
}

variable "enable_auto_lifecycle" {
  description = "Enable automatic start/stop lifecycle for Splunk instance. EventBridge starts Splunk on a schedule; per-boot script stops it after auto_shutdown_minutes."
  type        = bool
  default     = false
}

variable "auto_shutdown_minutes" {
  description = "Minutes after boot before Splunk auto-shuts down (requires enable_auto_lifecycle = true). Default 60 = 1 hour per start."
  type        = number
  default     = 60

  validation {
    condition = (
      var.auto_shutdown_minutes >= 1 &&
      floor(var.auto_shutdown_minutes) == var.auto_shutdown_minutes &&
      var.auto_shutdown_minutes <= 10080
    )
    error_message = "auto_shutdown_minutes must be an integer between 1 and 10080 (7 days)."
  }
}

variable "lifecycle_interval_hours" {
  description = "Hours between automatic Splunk starts via EventBridge Scheduler (requires enable_auto_lifecycle = true). Default 4 = 6 starts/day."
  type        = number
  default     = 4

  validation {
    condition     = var.lifecycle_interval_hours >= 1 && floor(var.lifecycle_interval_hours) == var.lifecycle_interval_hours
    error_message = "lifecycle_interval_hours must be an integer greater than or equal to 1."
  }
}

# --- criblio config layer (Phase 2: additive, default off) -------------------

variable "enable_criblio_config" {
  description = "Enable the criblio-managed Cribl config layer (modules/cribl-config/). When false, the layer is a no-op."
  type        = bool
  default     = false
}

variable "cribl_onprem_server_url" {
  description = "On-prem Cribl leader base URL (e.g. http://1.2.3.4:4200). Required when enable_criblio_config = true."
  type        = string
  default     = ""
}

variable "cribl_onprem_bearer_token" {
  description = "Bearer token for the on-prem Cribl leader. Sensitive. Source from SSM Parameter Store via the terragrunt inputs block."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cribl_cloud_client_id" {
  description = "Cribl.Cloud OAuth2 client_id. Optional; declared for future Cloud workspace use."
  type        = string
  default     = ""
}

variable "cribl_cloud_client_secret" {
  description = "Cribl.Cloud OAuth2 client_secret. Sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cribl_cloud_organization_id" {
  description = "Cribl.Cloud organization id."
  type        = string
  default     = ""
}

variable "cribl_cloud_workspace_id" {
  description = "Cribl.Cloud workspace id."
  type        = string
  default     = ""
}

variable "cribl_cloud_domain" {
  description = "Cribl.Cloud domain. Provider default is cribl.cloud."
  type        = string
  default     = "cribl.cloud"
}
