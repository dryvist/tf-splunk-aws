variable "worker_group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "leader_url" {
  description = "Cribl leader base URL (e.g. http://1.2.3.4:4200)."
  type        = string
}

variable "bearer_token" {
  description = "Bearer token for the leader API. Sensitive."
  type        = string
  sensitive   = true
}

variable "triggers" {
  description = "Map of content hashes from every upstream module. Any change re-runs commit + deploy."
  type        = map(string)
  default     = {}
}

variable "readiness_timeout_seconds" {
  description = "How long to wait for the leader API to become reachable before failing."
  type        = number
  default     = 300
}
