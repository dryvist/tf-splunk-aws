variable "pack_id" {
  description = "Pack ID (e.g. cribl-apache-logs)."
  type        = string
}

variable "group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "source_url" {
  description = "URL to a .crbl file (marketplace or release asset). Mutually exclusive with filename."
  type        = string
  default     = ""
}

variable "filename" {
  description = "Local path to a .crbl file. Mutually exclusive with source_url."
  type        = string
  default     = ""
}

variable "spec" {
  description = "Pack version spec (semver). Cribl applies updates only on version increase."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Pack tags map (data_type, domain, streamtags, technology)."
  type        = map(list(string))
  default     = {}
}
