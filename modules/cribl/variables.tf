# Cribl module variables.

variable "enable_cribl" {
  description = "Deploy the Cribl Stream and Edge instances. When false, this module creates nothing."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag applied to every resource."
  type        = string
  default     = "splunk-aws"
}

variable "cribl_stream_instance_type" {
  description = "Instance type for Cribl Stream (x86_64)."
  type        = string
  default     = "t3a.small"
}

variable "cribl_edge_instance_type" {
  description = "Instance type for the Cribl Edge Windows instance (x86_64)."
  type        = string
  default     = "t3a.medium"
}

variable "key_pair_name" {
  description = "EC2 key pair for the instances."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "Security group IDs to attach to Cribl instances."
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "Candidate subnets for instance placement (the first is used)."
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = "Whether to associate public IP addresses with Cribl instances."
  type        = bool
  default     = false
}

variable "instance_profile_name" {
  description = "IAM instance profile granting SSM access. May be null when enable_cribl = false."
  type        = string
  default     = null
}

variable "linux_ami_id" {
  description = "AMI for Cribl Stream (x86_64 Amazon Linux expected)."
  type        = string
}

variable "windows_ami_id" {
  description = "AMI for Cribl Edge (Windows Server expected)."
  type        = string
}

variable "windows_admin_password" {
  description = "Administrator password for the Windows Cribl Edge instance. May be null when enable_cribl = false."
  type        = string
  sensitive   = true
  default     = null
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
  description = "Base URL for Cribl package downloads."
  type        = string
  default     = "https://cdn.cribl.io"
}

variable "cribl_web_port" {
  description = "Port for the Cribl web UI and leader/worker communications. The leader config and the Edge worker connection both use it."
  type        = number
  default     = 4200
}
