variable "environment" {
  description = "Environment name (dev, stg, prod) — used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag identifying in-scope instances to auto-stop."
  type        = string
  default     = "splunk-aws"
}

variable "enable_auto_stop" {
  description = "Create the auto-stop guardrail (EventBridge Scheduler + Lambda). When false, no resources are created."
  type        = bool
  default     = false
}

variable "auto_stop_after_hours" {
  description = "Stop an in-scope instance once it has been running this many hours since its most recent start."
  type        = number
  default     = 48

  validation {
    condition = (
      var.auto_stop_after_hours >= 1 &&
      floor(var.auto_stop_after_hours) == var.auto_stop_after_hours &&
      var.auto_stop_after_hours <= 720
    )
    error_message = "auto_stop_after_hours must be an integer between 1 and 720 (30 days)."
  }
}

variable "check_interval_hours" {
  description = "How often the guardrail checks instance uptime, in hours. Lower = stops closer to the threshold."
  type        = number
  default     = 1

  validation {
    condition     = var.check_interval_hours >= 1 && floor(var.check_interval_hours) == var.check_interval_hours
    error_message = "check_interval_hours must be an integer greater than or equal to 1."
  }
}
