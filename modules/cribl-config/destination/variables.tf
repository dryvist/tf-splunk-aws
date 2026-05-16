variable "destination_id" {
  description = "Destination resource ID."
  type        = string
}

variable "group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "output_s3" {
  description = "S3 output config block. Set to null when using a different output type."
  type        = any
  default     = null
}

variable "output_splunk_hec" {
  description = "Splunk HEC output config block. Set to null when using a different output type."
  type        = any
  default     = null
}

variable "output_kafka" {
  description = "Kafka output config block. Set to null when using a different output type."
  type        = any
  default     = null
}

variable "output_syslog" {
  description = "Syslog output config block. Set to null when using a different output type."
  type        = any
  default     = null
}
