# Summon module outputs. All are null when enable_github_summon = false.
# Wire these into the repository's Actions variables (see README).

output "summon_role_arn" {
  description = "ARN of the role the summon workflow assumes via OIDC (repository variable SUMMON_ROLE_ARN)."
  value       = one(aws_iam_role.summon[*].arn)
}

output "scheduler_role_arn" {
  description = "ARN of the execution role for one-time stop-lease schedules (repository variable SUMMON_SCHEDULER_ROLE_ARN)."
  value       = one(aws_iam_role.lease_scheduler[*].arn)
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in use (created or reused)."
  value       = var.enable_github_summon ? local.oidc_provider_arn : null
}
