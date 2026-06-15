# Lifecycle Module — cost guardrail that auto-stops the Splunk/Cribl stack.
#
# An EventBridge Scheduler invokes a Lambda on a fixed cadence (default hourly).
# The Lambda stops any instance tagged Project = var.project_tag whose uptime
# exceeds var.auto_stop_after_hours. This replaces the previous Splunk-only,
# per-boot OS shutdown: a tag-driven API stop covers every instance in the stack
# (including the Windows Cribl Edge box) and never gets "stuck on".
#
# All resources are gated on var.enable_auto_stop.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

locals {
  count_enabled = var.enable_auto_stop ? 1 : 0
  function_name = "${var.environment}-splunk-auto-stop"
  # rate() requires singular "hour" for value 1, plural "hours" for all others.
  interval_unit = var.check_interval_hours == 1 ? "hour" : "hours"

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "terraform"
  }
}

data "archive_file" "auto_stop" {
  count       = local.count_enabled
  type        = "zip"
  source_file = "${path.module}/lambda/auto_stop.py"
  output_path = "${path.module}/.build/auto_stop.zip"
}

# --- Lambda execution role -------------------------------------------------
resource "aws_iam_role" "auto_stop" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "auto_stop" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop"
  role  = aws_iam_role.auto_stop[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeInstances"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        # Stop limited to instances carrying the in-scope Project tag.
        Sid      = "StopProjectInstances"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_tag }
        }
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.auto_stop[0].arn}:*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "auto_stop" {
  count             = local.count_enabled
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "auto_stop" {
  count            = local.count_enabled
  function_name    = local.function_name
  description      = "Stops Project=${var.project_tag} instances running longer than ${var.auto_stop_after_hours}h"
  role             = aws_iam_role.auto_stop[0].arn
  runtime          = "python3.13"
  handler          = "auto_stop.handler"
  filename         = data.archive_file.auto_stop[0].output_path
  source_code_hash = data.archive_file.auto_stop[0].output_base64sha256
  timeout          = 30

  environment {
    variables = {
      PROJECT_TAG           = var.project_tag
      AUTO_STOP_AFTER_HOURS = tostring(var.auto_stop_after_hours)
    }
  }

  # Ensure the log group exists (with our retention) before the function does.
  depends_on = [aws_cloudwatch_log_group.auto_stop]
  tags       = local.common_tags
}

# --- EventBridge Scheduler -> Lambda ---------------------------------------
resource "aws_iam_role" "scheduler" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop-scheduler"
  role  = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.auto_stop[0].arn
    }]
  })
}

resource "aws_scheduler_schedule" "auto_stop" {
  count       = local.count_enabled
  name        = "${var.environment}-splunk-auto-stop"
  description = "Stop Project=${var.project_tag} instances running longer than ${var.auto_stop_after_hours}h"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(${var.check_interval_hours} ${local.interval_unit})"

  target {
    arn      = aws_lambda_function.auto_stop[0].arn
    role_arn = aws_iam_role.scheduler[0].arn
  }
}
