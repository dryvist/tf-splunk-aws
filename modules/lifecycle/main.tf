# Lifecycle Module — cost guardrail that auto-stops the Splunk/Cribl stack.
#
# An EventBridge Scheduler runs the AWS-owned SSM Automation runbook
# `AWS-StopEC2Instance` on a schedule (default nightly), targeting every instance
# tagged Project = var.project_tag. Tag-driven and fully AWS-native — no Lambda,
# no custom code — so it covers all instances in the stack (including the Windows
# Cribl Edge box) and any future ones, and survives instance recreation.
#
# All resources are gated on var.enable_auto_stop.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  count_enabled = var.enable_auto_stop ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "terraform"
  }
}

# Execution role assumed by EventBridge Scheduler. The schedule starts the
# automation WITHOUT an AutomationAssumeRole, so the runbook runs under this same
# role — hence it carries both StartAutomationExecution and the ec2 stop/describe
# permissions, and no separate automation role or iam:PassRole is needed.
resource "aws_iam_role" "auto_stop" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop"

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

resource "aws_iam_role_policy" "auto_stop" {
  count = local.count_enabled
  name  = "${var.environment}-splunk-auto-stop"
  role  = aws_iam_role.auto_stop[0].id

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

resource "aws_scheduler_schedule" "auto_stop" {
  count       = local.count_enabled
  name        = "${var.environment}-splunk-auto-stop"
  description = "Stop Project=${var.project_tag} instances on schedule: ${var.stop_schedule_expression}"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.stop_schedule_expression

  # Universal target: invoke the AWS-owned AWS-StopEC2Instance runbook, resolving
  # the target instances by tag at execution time (no instance IDs to maintain).
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.auto_stop[0].arn

    input = jsonencode({
      DocumentName        = "AWS-StopEC2Instance"
      TargetParameterName = "InstanceId"
      Targets             = [{ Key = "tag:Project", Values = [var.project_tag] }]
    })
  }
}
