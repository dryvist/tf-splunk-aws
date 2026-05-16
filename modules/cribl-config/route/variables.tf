variable "routes_id" {
  description = "Routes resource ID. Use 'default' for the system routing table."
  type        = string
  default     = "default"
}

variable "group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "routes" {
  description = "Ordered list of routing rules. `output` must be jsonencode()'d by the caller."
  type = list(object({
    name        = string
    pipeline    = string
    filter      = optional(string, "true")
    final       = optional(bool, true)
    disabled    = optional(bool, false)
    description = optional(string, "")
    output      = optional(string)
  }))
  default = []
}
