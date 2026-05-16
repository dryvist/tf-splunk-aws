# Splunk Module Variables

variable "environment" {
  description = "Environment name (dev/stg/prod)"
  type        = string
}

variable "splunk_instance_type" {
  description = "Instance type for Splunk instance"
  type        = string
  default     = "t4g.small"
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

variable "splunk_password_ssm_name" {
  description = "SSM Parameter Store name for the Splunk admin password"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for instances (optional)"
  type        = string
  default     = null
}

variable "splunk_security_group_ids" {
  description = "Security group IDs for Splunk instance"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs for Splunk instance placement"
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with the Splunk instance"
  type        = bool
  default     = false
}

variable "splunk_instance_profile_name" {
  description = "IAM instance profile name for Splunk instance"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the Splunk instance"
  type        = string
}

variable "splunk_version" {
  description = "Splunk Enterprise version to install"
  type        = string
  default     = "9.3.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.splunk_version))
    error_message = "Splunk version must be in X.Y.Z format (e.g., 9.3.2)."
  }
}

variable "splunk_build" {
  description = "Splunk Enterprise build hash for the download URL"
  type        = string
  default     = "d8bb32809498"

  validation {
    condition     = can(regex("^[a-f0-9]{12}$", var.splunk_build))
    error_message = "Splunk build must be a 12-character hexadecimal string."
  }
}

variable "enable_auto_lifecycle" {
  description = "Enable automatic start/stop lifecycle for Splunk instance"
  type        = bool
  default     = false
}

variable "auto_shutdown_minutes" {
  description = "Minutes after boot before Splunk auto-shuts down (requires enable_auto_lifecycle = true)"
  type        = number
  default     = 60

  validation {
    condition     = var.auto_shutdown_minutes >= 1 && floor(var.auto_shutdown_minutes) == var.auto_shutdown_minutes
    error_message = "auto_shutdown_minutes must be an integer greater than or equal to 1."
  }
}

variable "lifecycle_interval_hours" {
  description = "Hours between automatic Splunk starts via EventBridge Scheduler (requires enable_auto_lifecycle = true)"
  type        = number
  default     = 4

  validation {
    condition     = var.lifecycle_interval_hours >= 1 && floor(var.lifecycle_interval_hours) == var.lifecycle_interval_hours
    error_message = "lifecycle_interval_hours must be an integer greater than or equal to 1."
  }
}
