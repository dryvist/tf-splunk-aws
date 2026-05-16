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

# --- on-prem leader (default path) -------------------------------------------

variable "onprem_server_url" {
  description = "On-prem Cribl leader base URL (e.g. http://1.2.3.4:4200). Provider also accepts CRIBL_ONPREM_SERVER_URL env var."
  type        = string
  default     = ""
}

variable "onprem_bearer_token" {
  description = "Bearer token for the on-prem leader. Sourced from SSM Parameter Store by the caller; passed sensitive. Provider also accepts CRIBL_BEARER_TOKEN env var."
  type        = string
  default     = ""
  sensitive   = true
}

# Cribl.Cloud provider auth lives at the root (modules/main.tf). This submodule
# accepts the `criblio.cloud` aliased provider but does not currently configure
# resources against it — when Cloud workspace work begins, those resources will
# go in a child module that takes `providers = { criblio = criblio.cloud }`.
