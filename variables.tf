# Root module variables.
#
# Every variable has a working default so `tofu plan` succeeds with zero
# inputs. Environment-specific values live in envs/<env>.tfvars; secrets are
# passed via TF_VAR_* environment variables or generated at apply time.

# --- Deployment context -------------------------------------------------------

variable "environment" {
  description = "Environment name used to namespace all resources (e.g. dev, stg, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 chars: lowercase letters, digits, hyphens; starting with a letter."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project_tag" {
  description = "Value of the Project tag applied to every resource. The auto-stop guardrail targets instances by this tag, so all instances in scope must share it."
  type        = string
  default     = "splunk-aws"
}

# --- Feature toggles ----------------------------------------------------------

variable "enable_splunk" {
  description = "Deploy the Splunk Enterprise instance and its supporting resources (security group, IAM role, SSM password parameter). Splunk and Cribl can be enabled independently."
  type        = bool
  default     = true
}

variable "enable_cribl" {
  description = "Deploy the Cribl Stream (Linux) and Cribl Edge (Windows) instances and their supporting resources. Splunk and Cribl can be enabled independently."
  type        = bool
  default     = false
}

variable "enable_auto_stop" {
  description = "Stop every Project-tagged instance on stop_schedule_expression via the AWS-StopEC2Instance runbook. On by default — this is the primary cost control. A daily schedule caps runtime at under 24 hours."
  type        = bool
  default     = true
}

variable "stop_schedule_expression" {
  description = "EventBridge Scheduler expression for the scheduled stop. Default nightly 08:00 UTC."
  type        = string
  default     = "cron(0 8 * * ? *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(", var.stop_schedule_expression))
    error_message = "stop_schedule_expression must be a cron(...) or rate(...) expression."
  }
}

# --- Network ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the subnets. Defaults to the first two available AZs in aws_region."
  type        = list(string)
  default     = null
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (NAT instance; workload instances when splunk_public_access = true)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (default workload placement)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# --- Access control -----------------------------------------------------------

variable "admin_ip_cidrs" {
  description = "Operator egress CIDRs granted access to every operator-facing surface (Splunk Web, HEC, management, Cribl). Convenience superset of the per-surface allowlists below. Typically set via TF_VAR_admin_ip_cidrs."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_ip_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each admin_ip_cidrs entry must be a valid CIDR block, e.g. 203.0.113.7/32."
  }
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed access to Splunk Web. Creates a security group rule whenever non-empty, regardless of splunk_public_access (useful for VPN/peering access to private instances)."
  type        = list(string)
  default     = []
}

variable "hec_allowed_cidrs" {
  description = "CIDR blocks allowed to send data to Splunk HEC. Set to the egress IPs of your data sources."
  type        = list(string)
  default     = []
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks for management ports (RDP, Splunk management) — always restricted, never affected by allow_all_ips. SSH is controlled by ssh_allowed_cidrs."
  type        = list(string)
  default     = []
}

variable "cribl_allowed_cidrs" {
  description = "CIDR blocks for Cribl ports (web/leader UI and data ingest) — affected by allow_all_ips."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access (port 22). Empty list (the default) creates no SSH rule at all; use SSM Session Manager instead."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each ssh_allowed_cidrs entry must be a valid CIDR block, e.g. 203.0.113.0/24."
  }
}

variable "allow_all_ips" {
  description = "Open Splunk Web, HEC, and Cribl ports to 0.0.0.0/0, overriding their allowlists. Intended only for short-lived testing; set via TF_VAR_allow_all_ips=true rather than committing it."
  type        = bool
  default     = false
}

# --- Service ports ------------------------------------------------------------
# Security group rules and service URLs derive from these. Changing a port here
# only changes what is *allowed and advertised* — the service must be configured
# to actually listen on the new port (Splunk and Cribl both default to these).

variable "splunk_web_port" {
  description = "Port Splunk Web listens on."
  type        = number
  default     = 8000
}

variable "splunk_hec_port" {
  description = "Port the Splunk HTTP Event Collector listens on."
  type        = number
  default     = 8088
}

variable "splunk_management_port" {
  description = "Port the Splunk management API (splunkd) listens on."
  type        = number
  default     = 8089
}

variable "splunk_s2s_port" {
  description = "Port for Splunk-to-Splunk forwarding (splunktcp)."
  type        = number
  default     = 9997
}

variable "cribl_web_port" {
  description = "Port for the Cribl web UI and leader/worker communications."
  type        = number
  default     = 4200
}

variable "cribl_data_port" {
  description = "Port for Cribl data ingest."
  type        = number
  default     = 9997
}

# --- Instances ----------------------------------------------------------------

variable "key_pair_name" {
  description = "Existing EC2 key pair to use for all instances. Leave null to generate a throwaway key pair with the environment."
  type        = string
  default     = null
}

variable "generated_password_length" {
  description = "Length of generated admin passwords (Splunk admin, Windows Administrator) when none are supplied."
  type        = number
  default     = 24

  validation {
    condition     = var.generated_password_length >= 12 && var.generated_password_length <= 128
    error_message = "generated_password_length must be between 12 and 128."
  }
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance. ARM/Graviton types work here (the NAT AMI is arm64)."
  type        = string
  default     = "t4g.nano"
}

variable "splunk_instance_type" {
  description = "Instance type for the Splunk instance. Must be x86_64 — Splunk Enterprise has no public ARM64 release."
  type        = string
  default     = "t3a.small"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]g\\.)", var.splunk_instance_type))
    error_message = "splunk_instance_type must be x86_64. ARM/Graviton families (e.g., t4g.*, c6g.*, m6g.*, a1.*) are not supported — Splunk Enterprise has no public ARM64 release."
  }
}

variable "splunk_root_volume_size" {
  description = "Size of the Splunk root volume (GB)."
  type        = number
  default     = 20
}

variable "splunk_data_volume_size" {
  description = "Size of the dedicated Splunk data volume mounted at /opt/splunk (GB). Index data lives here."
  type        = number
  default     = 50
}

variable "cribl_stream_instance_type" {
  description = "Instance type for Cribl Stream. Must be x86_64."
  type        = string
  default     = "t3a.small"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]+g[a-z]*\\.)", var.cribl_stream_instance_type))
    error_message = "cribl_stream_instance_type must be x86_64. ARM/Graviton families are not supported."
  }
}

variable "cribl_edge_instance_type" {
  description = "Instance type for the Cribl Edge Windows instance. Must be x86_64."
  type        = string
  default     = "t3a.medium"

  validation {
    condition     = !can(regex("(^a1\\.|[0-9]+g[a-z]*\\.)", var.cribl_edge_instance_type))
    error_message = "cribl_edge_instance_type must be x86_64. ARM/Graviton families are not supported."
  }
}

variable "splunk_public_access" {
  description = "Place workload instances in a public subnet with public IPs. When false (the default) they live in private subnets behind the NAT instance."
  type        = bool
  default     = false
}

# --- AMI overrides ------------------------------------------------------------
# Leave null to use the latest matching Amazon-owned AMI; set to pin an image
# or substitute a hardened base AMI.

variable "nat_ami_id" {
  description = "Override AMI for the NAT instance (arm64 Amazon Linux expected)."
  type        = string
  default     = null
}

variable "splunk_ami_id" {
  description = "Override AMI for the Splunk instance (x86_64 Amazon Linux expected)."
  type        = string
  default     = null
}

variable "cribl_stream_ami_id" {
  description = "Override AMI for the Cribl Stream instance (x86_64 Amazon Linux expected)."
  type        = string
  default     = null
}

variable "cribl_edge_ami_id" {
  description = "Override AMI for the Cribl Edge instance (Windows Server expected)."
  type        = string
  default     = null
}

# --- Software versions --------------------------------------------------------

variable "splunk_version" {
  description = "Splunk Enterprise version to install."
  type        = string
  default     = "9.4.9"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.splunk_version))
    error_message = "Splunk version must be in X.Y.Z format (e.g., 9.4.9)."
  }
}

variable "splunk_build" {
  description = "Splunk Enterprise build hash used in the download URL."
  type        = string
  default     = "03bb451d4e07"

  validation {
    condition     = can(regex("^[a-f0-9]{12}$", var.splunk_build))
    error_message = "Splunk build must be a 12-character hexadecimal string."
  }
}

variable "splunk_download_base_url" {
  description = "Base URL for Splunk package downloads. Point at an internal mirror if instances cannot reach the vendor CDN."
  type        = string
  default     = "https://download.splunk.com"
}

variable "cribl_version" {
  description = "Cribl Stream/Edge version to install."
  type        = string
  default     = "4.16.1"
}

variable "cribl_build" {
  description = "Cribl build identifier used in the download URL."
  type        = string
  default     = "20904e45"
}

variable "cribl_download_base_url" {
  description = "Base URL for Cribl package downloads. Point at an internal mirror if instances cannot reach the vendor CDN."
  type        = string
  default     = "https://cdn.cribl.io"
}

# --- Secrets ------------------------------------------------------------------

variable "splunk_admin_password" {
  description = "Splunk admin password. Leave null (the default) to generate a random password per deployment; retrieve it from the access_credentials output. Set via TF_VAR_splunk_admin_password."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.splunk_admin_password == null || var.splunk_admin_password == "" || length(var.splunk_admin_password) >= 8
    error_message = "Splunk admin password must be at least 8 characters when provided."
  }
}

# --- Cribl config layer (criblio provider) ------------------------------------

variable "enable_criblio_config" {
  description = "Enable the criblio-managed Cribl configuration layer (modules/cribl-config). When false, the layer is a no-op."
  type        = bool
  default     = false
}

variable "cribl_onprem_server_url" {
  description = "On-prem Cribl leader base URL (e.g. http://10.0.10.5:4200). Required when enable_criblio_config = true."
  type        = string
  default     = ""
}

variable "cribl_onprem_bearer_token" {
  description = "Bearer token for the on-prem Cribl leader. Set via TF_VAR_cribl_onprem_bearer_token or CRIBL_BEARER_AUTH."
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
  description = "Cribl.Cloud OAuth2 client_secret."
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
