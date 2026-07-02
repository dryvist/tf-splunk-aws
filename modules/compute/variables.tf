# Compute module variables.

variable "environment" {
  description = "Environment name used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag applied to every resource."
  type        = string
  default     = "splunk-aws"
}

variable "nat_instance_type" {
  description = "Instance type for NAT instance"
  type        = string
  default     = "t4g.nano"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for instances (optional)"
  type        = string
  default     = null
}

variable "nat_security_group_id" {
  description = "Security group ID for NAT instance"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID for the NAT instance"
  type        = string
}
