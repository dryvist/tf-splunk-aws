variable "worker_group_id" {
  description = "Target worker group ID."
  type        = string
}

variable "triggers" {
  description = "Map of content hashes from every upstream module. Any change forces a fresh commit + deploy via terraform_data.trigger replace_triggered_by."
  type        = map(string)
  default     = {}
}
