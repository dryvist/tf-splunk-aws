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
  description = "Create the auto-stop guardrail (EventBridge Scheduler + AWS-StopEC2Instance runbook). When false, no resources are created."
  type        = bool
  default     = false
}

variable "stop_schedule_expression" {
  description = "EventBridge Scheduler expression for when to stop in-scope instances. Default nightly 08:00 UTC; use e.g. \"rate(48 hours)\" for a looser lease."
  type        = string
  default     = "cron(0 8 * * ? *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(", var.stop_schedule_expression))
    error_message = "stop_schedule_expression must be a cron(...) or rate(...) expression."
  }
}
