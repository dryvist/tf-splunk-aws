variable "pipeline_id" {
  description = "Pipeline ID."
  type        = string
}

variable "group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "description" {
  description = "Pipeline description."
  type        = string
  default     = ""
}

variable "async_func_timeout" {
  description = "Async function timeout in ms."
  type        = number
  default     = 5000
}

variable "output_destination" {
  description = "Default destination ID for pipeline output."
  type        = string
  default     = ""
}

variable "streamtags" {
  description = "Stream tags."
  type        = list(string)
  default     = []
}

variable "functions" {
  description = "Ordered list of pipeline functions. Each function's `conf` field must be jsonencode()'d by the caller."
  type = list(object({
    id          = string
    filter      = optional(string, "true")
    disabled    = optional(bool, false)
    final       = optional(bool, false)
    description = optional(string, "")
    conf        = string
  }))
  default = []
}
