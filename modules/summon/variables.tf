# Summon module variables.

variable "enable_github_summon" {
  description = "Create the GitHub Actions OIDC role and lease scheduler role. When false, this module creates nothing."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name used to namespace resources."
  type        = string
}

variable "project_tag" {
  description = "Value of the Project tag identifying instances the summon role may start/stop."
  type        = string
  default     = "splunk-aws"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) trusted to assume the summon role."
  type        = string
  default     = ""

  validation {
    condition = !var.enable_github_summon || can(
      regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository)
    )
    error_message = "github_repository (owner/name) is required when enable_github_summon = true."
  }
}

variable "github_branch" {
  description = "Branch whose workflow runs may assume the summon role."
  type        = string
  default     = "main"
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC identity provider to reuse. Leave null to create one."
  type        = string
  default     = null
}
