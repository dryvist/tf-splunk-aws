output "auto_stop_function_name" {
  description = "Name of the auto-stop Lambda function (null when disabled)."
  value       = one(aws_lambda_function.auto_stop[*].function_name)
}

output "auto_stop_schedule_name" {
  description = "Name of the EventBridge schedule that triggers the auto-stop Lambda (null when disabled)."
  value       = one(aws_scheduler_schedule.auto_stop[*].name)
}
