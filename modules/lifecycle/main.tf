# Lifecycle module — cost guardrails that stop the stack automatically.
#
# Two independent mechanisms, both tag-driven (no instance IDs to maintain):
#
#   1. Uptime sweep (enable_auto_stop, the default guardrail): an EventBridge
#      Scheduler invokes a small Lambda every hour; the Lambda stops any
#      Project-tagged instance whose LaunchTime is older than
#      max_runtime_hours. Because LaunchTime resets on every start, this is a
#      true "24 hours after it was started" limit — however the instance was
#      started (summon workflow, console, CLI).
#
#   2. Fixed schedule (enable_scheduled_stop, off by default): an EventBridge
#      Scheduler runs the AWS-owned AWS-StopEC2Instance SSM runbook at a set
#      time (e.g. nightly), stopping the whole stack regardless of uptime.
#
# Cost: both mechanisms sit comfortably inside the EventBridge Scheduler and
# Lambda free tiers (~730 invocations/month of a 128 MB function).

terraform {
  required_version = ">= 1.6"
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
  sweep_enabled = var.enable_auto_stop ? 1 : 0
  cron_enabled  = var.enable_scheduled_stop ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }
}

# --- Uptime sweep (Lambda) ------------------------------------------------------

data "archive_file" "auto_stop" {
  count = local.sweep_enabled

  type        = "zip"
  source_file = "${path.module}/lambda/auto_stop.py"
  output_path = "${path.module}/lambda/auto_stop.zip"
}

resource "aws_iam_role" "sweep_lambda" {
  count = local.sweep_enabled
  name  = "${var.environment}-${var.project_tag}-uptime-sweep-lambda"

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

resource "aws_iam_role_policy" "sweep_lambda" {
  count = local.sweep_enabled
  name  = "${var.environment}-${var.project_tag}-uptime-sweep-lambda"
  role  = aws_iam_role.sweep_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
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
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_tag }
        }
      },
    ]
  })
}

resource "aws_lambda_function" "auto_stop" {
  count = local.sweep_enabled

  function_name    = "${var.environment}-${var.project_tag}-uptime-sweep"
  description      = "Stops Project=${var.project_tag} instances running longer than ${var.max_runtime_hours}h"
  role             = aws_iam_role.sweep_lambda[0].arn
  filename         = data.archive_file.auto_stop[0].output_path
  source_code_hash = data.archive_file.auto_stop[0].output_base64sha256
  handler          = "auto_stop.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      PROJECT_TAG       = var.project_tag
      MAX_RUNTIME_HOURS = tostring(var.max_runtime_hours)
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "auto_stop" {
  count = local.sweep_enabled

  name              = "/aws/lambda/${var.environment}-${var.project_tag}-uptime-sweep"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_iam_role" "sweep_scheduler" {
  count = local.sweep_enabled
  name  = "${var.environment}-${var.project_tag}-uptime-sweep-scheduler"

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

resource "aws_iam_role_policy" "sweep_scheduler" {
  count = local.sweep_enabled
  name  = "${var.environment}-${var.project_tag}-uptime-sweep-scheduler"
  role  = aws_iam_role.sweep_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.auto_stop[0].arn
    }]
  })
}

resource "aws_scheduler_schedule" "uptime_sweep" {
  count       = local.sweep_enabled
  name        = "${var.environment}-${var.project_tag}-uptime-sweep"
  description = "Hourly sweep stopping Project=${var.project_tag} instances up longer than ${var.max_runtime_hours}h"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(1 hour)"

  target {
    arn      = aws_lambda_function.auto_stop[0].arn
    role_arn = aws_iam_role.sweep_scheduler[0].arn
  }
}

# --- Fixed-schedule stop (SSM runbook, no Lambda) -------------------------------

# Execution role assumed by EventBridge Scheduler. The schedule starts the
# automation WITHOUT an AutomationAssumeRole, so the runbook runs under this
# same role — hence it carries both StartAutomationExecution and the ec2
# stop/describe permissions, and no separate automation role is needed.
resource "aws_iam_role" "scheduled_stop" {
  count = local.cron_enabled
  name  = "${var.environment}-${var.project_tag}-scheduled-stop"

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

resource "aws_iam_role_policy" "scheduled_stop" {
  count = local.cron_enabled
  name  = "${var.environment}-${var.project_tag}-scheduled-stop"
  role  = aws_iam_role.scheduled_stop[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStopAutomation"
        Effect   = "Allow"
        Action   = ["ssm:StartAutomationExecution"]
        Resource = "arn:aws:ssm:*:*:automation-definition/AWS-StopEC2Instance:*"
      },
      {
        Sid      = "DescribeInstances"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      },
      {
        Sid      = "StopProjectInstances"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_tag }
        }
      },
    ]
  })
}

resource "aws_scheduler_schedule" "scheduled_stop" {
  count       = local.cron_enabled
  name        = "${var.environment}-${var.project_tag}-scheduled-stop"
  description = "Stop Project=${var.project_tag} instances on schedule: ${var.stop_schedule_expression}"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.stop_schedule_expression

  # Universal target: invoke the AWS-owned AWS-StopEC2Instance runbook,
  # resolving target instances by tag at execution time.
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.scheduled_stop[0].arn

    input = jsonencode({
      DocumentName        = "AWS-StopEC2Instance"
      TargetParameterName = "InstanceId"
      Targets             = [{ Key = "tag:Project", Values = [var.project_tag] }]
    })
  }
}
