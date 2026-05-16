output "worker_group_id" {
  description = "ID of the managed worker group (null when disabled)."
  value       = try(module.worker_group[0].id, null)
}

output "enabled" {
  description = "Whether the criblio config layer is active."
  value       = local.enabled
}
