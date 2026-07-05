# Splunk module variables.

variable "enable_splunk" {
  description = "Deploy the Splunk instance and its supporting resources. When false, this module creates nothing."
  type        = bool
  default     = true
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

variable "splunk_instance_type" {
  description = "Instance type for the Splunk instance (must be x86_64)."
  type        = string
  default     = "t3a.small"
}

variable "splunk_root_volume_size" {
  description = "Size of the root volume (GB)."
  type        = number
  default     = 20
}

variable "splunk_data_volume_size" {
  description = "Size of the dedicated data volume mounted at /opt/splunk (GB)."
  type        = number
  default     = 50
}

variable "splunk_password_ssm_name" {
  description = "SSM Parameter Store name the instance reads the admin password from at boot. May be null when enable_splunk = false."
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "EC2 key pair for the instance."
  type        = string
  default     = null
}

variable "splunk_security_group_ids" {
  description = "Security group IDs to attach to the Splunk instance."
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "Candidate subnets for instance placement (the first is used)."
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with the Splunk instance."
  type        = bool
  default     = false
}

variable "splunk_instance_profile_name" {
  description = "IAM instance profile granting SSM access and password retrieval. May be null when enable_splunk = false."
  type        = string
  default     = null
}

variable "ami_id" {
  description = "AMI for the Splunk instance (x86_64 Amazon Linux expected)."
  type        = string
}

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
  description = "Base URL for Splunk package downloads."
  type        = string
  default     = "https://download.splunk.com"
}

variable "splunk_web_port" {
  description = "Port Splunk Web listens on (used to build the web URL output)."
  type        = number
  default     = 8000
}
