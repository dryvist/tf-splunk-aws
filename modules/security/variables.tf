# Security module variables.

variable "environment" {
  description = "Environment name used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag applied to every resource."
  type        = string
  default     = "splunk-aws"
}

variable "vpc_id" {
  description = "ID of the VPC the security groups belong to."
  type        = string
}

variable "vpc_cidr_blocks" {
  description = "VPC CIDR blocks granted access to intra-VPC service ports."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs whose outbound traffic the NAT instance forwards."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_splunk" {
  description = "Create the Splunk security group, IAM role/profile, and SSM password parameter."
  type        = bool
  default     = true
}

variable "enable_cribl" {
  description = "Create the Cribl security groups and IAM role/profile."
  type        = bool
  default     = false
}

variable "splunk_admin_password" {
  description = "Splunk admin password to store in SSM Parameter Store. May be null when enable_splunk = false."
  type        = string
  sensitive   = true
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access (port 22). Empty list creates no SSH rule."
  type        = list(string)
  default     = []
}

variable "hec_allowed_cidrs" {
  description = "CIDR blocks allowed to send data to Splunk HEC."
  type        = list(string)
  default     = []
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed external access to Splunk Web."
  type        = list(string)
  default     = []
}

variable "management_allowed_cidrs" {
  description = "CIDR blocks for management ports (RDP, Splunk management API) — always restricted, never affected by allow_all_ips."
  type        = list(string)
  default     = []
}

variable "cribl_allowed_cidrs" {
  description = "CIDR blocks for Cribl web/leader and data-ingest ports — affected by allow_all_ips."
  type        = list(string)
  default     = []
}

variable "allow_all_ips" {
  description = "Open Splunk Web, HEC, and Cribl ports to 0.0.0.0/0, overriding their allowlists."
  type        = bool
  default     = false
}

# --- Service ports ----------------------------------------------------------

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
