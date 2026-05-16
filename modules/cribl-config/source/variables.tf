variable "source_id" {
  description = "Source resource ID."
  type        = string
}

variable "group_id" {
  description = "Target worker group ID."
  type        = string
}

# One of the four input blocks must be set. Untyped (any) so callers can pass
# the rich, polymorphic config the provider expects without us re-typing
# every field per-input-type. The provider validates the shape at apply.

variable "input_http" {
  description = "HTTP input config block. Set to null when using a different input type."
  type        = any
  default     = null
}

variable "input_tcp" {
  description = "TCP input config block. Set to null when using a different input type."
  type        = any
  default     = null
}

variable "input_syslog" {
  description = "Syslog input config block. Set to null when using a different input type."
  type        = any
  default     = null
}

variable "input_splunk_hec" {
  description = "Splunk HEC input config block. Set to null when using a different input type."
  type        = any
  default     = null
}
