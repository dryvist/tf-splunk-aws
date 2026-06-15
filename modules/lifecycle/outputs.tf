output "auto_stop_function_name" {
  description = "Name of the auto-stop Lambda function (null when disabled)."
  value       = var.enable_auto_stop ? aws_lambda_function.auto_stop[0].function_name : null
}

output "auto_stop_schedule_name" {
  description = "Name of the EventBridge schedule that triggers the auto-stop Lambda (null when disabled)."
  value       = var.enable_auto_stop ? aws_scheduler_schedule.auto_stop[0].name : null
}
