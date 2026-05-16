variable "enable_criblio_config" {
  description = "Master toggle for the criblio-managed config layer. When false, the entire module is a no-op."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Environment name (dev/stg/prod). Used as a streamtag."
  type        = string
}

variable "default_worker_group_id" {
  description = "Worker group ID managed by this module. Cribl ships with 'default'; override only if migrating to a named group."
  type        = string
  default     = "default"
}

# Provider auth (on-prem `server_url` + `bearer_auth`, Cloud OAuth2) lives at
# the root (modules/main.tf). This submodule just accepts the aliased providers
# via `providers = { criblio = criblio.onprem }` on each child module.
