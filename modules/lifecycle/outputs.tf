output "auto_stop_schedule_name" {
  description = "Name of the EventBridge schedule that triggers the auto-stop runbook (null when disabled)."
  value       = one(aws_scheduler_schedule.auto_stop[*].name)
}
