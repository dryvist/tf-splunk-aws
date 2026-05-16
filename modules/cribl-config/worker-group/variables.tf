variable "group_id" {
  description = "Worker group ID."
  type        = string
}

variable "name" {
  description = "Human-readable name. Defaults to group_id when empty."
  type        = string
  default     = ""
}

variable "description" {
  description = "Worker group description."
  type        = string
  default     = ""
}

variable "product" {
  description = "Cribl product for this group: stream or edge."
  type        = string
  default     = "stream"
  validation {
    condition     = contains(["stream", "edge"], var.product)
    error_message = "product must be 'stream' or 'edge'."
  }
}

variable "on_prem" {
  description = "True for on-prem groups, false for Cribl.Cloud provisioned groups."
  type        = bool
  default     = true
}

variable "streamtags" {
  description = "Stream tags for grouping/filtering."
  type        = list(string)
  default     = []
}
