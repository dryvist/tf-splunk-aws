# Lifecycle module — stops the stack on a schedule.
#
# An EventBridge Scheduler invokes the AWS-owned AWS-StopEC2Instance SSM
# runbook on stop_schedule_expression (default nightly), targeting every
# instance tagged Project = var.project_tag. Tag-driven and fully AWS-native —
# no Lambda, no custom code — so it covers all instances in the stack (Splunk,
# Cribl Stream, Cribl Edge, NAT) and any future ones, however they were started.
#
# All resources are gated on var.enable_auto_stop.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  enabled = var.enable_auto_stop ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }
}

# Execution role assumed by EventBridge Scheduler. The schedule starts the
# automation without an AutomationAssumeRole, so the runbook runs under this
# same role — it therefore carries both StartAutomationExecution and the ec2
# stop/describe permissions, and no separate automation role is needed.
resource "aws_iam_role" "auto_stop" {
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-auto-stop"

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
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-auto-stop"
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
  count       = local.enabled
  name        = "${var.environment}-${var.project_tag}-auto-stop"
  description = "Stop Project=${var.project_tag} instances on schedule: ${var.stop_schedule_expression}"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.stop_schedule_expression

  # Universal target: invoke the AWS-owned AWS-StopEC2Instance runbook,
  # resolving target instances by tag at execution time (no instance IDs to
  # maintain).
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
