# Lifecycle module outputs.

output "auto_stop_schedule_name" {
  description = "Name of the EventBridge schedule that triggers the stop runbook (null when enable_auto_stop = false)."
  value       = one(aws_scheduler_schedule.auto_stop[*].name)
}
