# Lifecycle module outputs.

output "uptime_sweep_function_name" {
  description = "Name of the uptime-sweep Lambda function (null when enable_auto_stop = false)."
  value       = one(aws_lambda_function.auto_stop[*].function_name)
}

output "uptime_sweep_schedule_name" {
  description = "Name of the hourly EventBridge schedule that triggers the uptime sweep (null when enable_auto_stop = false)."
  value       = one(aws_scheduler_schedule.uptime_sweep[*].name)
}

output "scheduled_stop_schedule_name" {
  description = "Name of the fixed-schedule stop schedule (null when enable_scheduled_stop = false)."
  value       = one(aws_scheduler_schedule.scheduled_stop[*].name)
}
