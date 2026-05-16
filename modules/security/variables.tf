# Security Module Variables

variable "environment" {
  description = "Environment name (dev/stg/prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr_blocks" {
  description = "List of CIDR blocks for VPC access"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "splunk_admin_password" {
  description = "Admin password for Splunk (stored in SSM Parameter Store)"
  type        = string
  sensitive   = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access to instances (port 22). Set to [] to disable SSH."
  type        = list(string)
  default     = []
}

variable "hec_allowed_cidrs" {
  description = "CIDR blocks allowed to send data to Splunk HEC (port 8088). Set to your on-prem/cloud source IPs."
  type        = list(string)
  default     = []
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed access to Splunk Web (port 8000) from the internet. Set to [] to restrict to VPC only."
  type        = list(string)
  default     = []
}

variable "allow_all_ips" {
  description = "Override web_allowed_cidrs and hec_allowed_cidrs to 0.0.0.0/0."
  type        = bool
  default     = false
}

variable "enable_cribl" {
  description = "Enable Cribl Stream and Edge resources (security groups, IAM)"
  type        = bool
  default     = true
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
