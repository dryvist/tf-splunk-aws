# Lifecycle module variables.

variable "environment" {
  description = "Environment name used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag identifying in-scope instances to stop."
  type        = string
  default     = "splunk-aws"
}

variable "enable_auto_stop" {
  description = "Create the uptime sweep: an hourly Lambda that stops any Project-tagged instance running longer than max_runtime_hours. When false, no sweep resources are created."
  type        = bool
  default     = true
}

variable "max_runtime_hours" {
  description = "Maximum continuous uptime (hours, measured from LaunchTime) before the sweep stops an instance."
  type        = number
  default     = 24

  validation {
    condition     = var.max_runtime_hours >= 1 && var.max_runtime_hours <= 168
    error_message = "max_runtime_hours must be between 1 and 168 (one week)."
  }
}

variable "enable_scheduled_stop" {
  description = "Additionally stop the whole stack on a fixed schedule via the AWS-StopEC2Instance runbook, independent of uptime."
  type        = bool
  default     = false
}

variable "stop_schedule_expression" {
  description = "EventBridge Scheduler expression for the fixed-schedule stop (requires enable_scheduled_stop)."
  type        = string
  default     = "cron(0 8 * * ? *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(", var.stop_schedule_expression))
    error_message = "stop_schedule_expression must be a cron(...) or rate(...) expression."
  }
}
