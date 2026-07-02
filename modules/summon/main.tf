# Summon module — lets authorized GitHub users start/stop this environment
# with zero AWS credentials of their own.
#
# The .github/workflows/summon.yml workflow authenticates to AWS via GitHub
# Actions OIDC and assumes the role created here. The role can only:
#   * start/stop instances carrying the Project tag,
#   * describe instances (to report IPs in the job summary),
#   * create/delete one-time "stop lease" schedules named
#     <environment>-<project_tag>-lease-*, passing only the lease scheduler
#     role created here.
#
# The lease gives a summoned environment a predictable stop time; the
# lifecycle module's uptime sweep remains the backstop for anything started
# outside the workflow.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {
  count = local.enabled
}

data "aws_partition" "current" {
  count = local.enabled
}

locals {
  enabled = var.enable_github_summon ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }

  lease_name_prefix = "${var.environment}-${var.project_tag}-lease"

  # Reuse an existing OIDC provider when given; otherwise create one below.
  # Null when the module is disabled (nothing references it then).
  oidc_provider_arn = var.enable_github_summon ? coalesce(
    var.github_oidc_provider_arn,
    try(aws_iam_openid_connect_provider.github[0].arn, null)
  ) : null
}

# GitHub Actions OIDC identity provider. An AWS account can hold only one
# provider per issuer URL — pass github_oidc_provider_arn instead if your
# account already has one.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_summon && var.github_oidc_provider_arn == null ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

# Role assumed by the summon workflow. Trust is scoped to workflow runs on the
# default branch of the configured repository.
resource "aws_iam_role" "summon" {
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-summon"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "summon" {
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-summon"
  role  = aws_iam_role.summon[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeInstances"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      },
      {
        # Start/stop limited to instances carrying the in-scope Project tag.
        Sid      = "StartStopProjectInstances"
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = "arn:${data.aws_partition.current[0].partition}:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_tag }
        }
      },
      {
        # Manage only the one-time stop-lease schedules the workflow creates.
        Sid    = "ManageStopLeases"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule"
        ]
        Resource = "arn:${data.aws_partition.current[0].partition}:scheduler:*:${data.aws_caller_identity.current[0].account_id}:schedule/default/${local.lease_name_prefix}-*"
      },
      {
        Sid      = "PassLeaseSchedulerRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.lease_scheduler[0].arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" }
        }
      },
    ]
  })
}

# Execution role for the one-time stop-lease schedules. The lease invokes the
# AWS-owned AWS-StopEC2Instance runbook without an AutomationAssumeRole, so
# this role carries both the automation-start and ec2-stop permissions
# (mirrors the lifecycle module's scheduled-stop role).
resource "aws_iam_role" "lease_scheduler" {
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-lease-scheduler"

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

resource "aws_iam_role_policy" "lease_scheduler" {
  count = local.enabled
  name  = "${var.environment}-${var.project_tag}-lease-scheduler"
  role  = aws_iam_role.lease_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStopAutomation"
        Effect   = "Allow"
        Action   = ["ssm:StartAutomationExecution"]
        Resource = "arn:${data.aws_partition.current[0].partition}:ssm:*:*:automation-definition/AWS-StopEC2Instance:*"
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
        Resource = "arn:${data.aws_partition.current[0].partition}:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_tag }
        }
      },
    ]
  })
}
