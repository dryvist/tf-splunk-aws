output "id" {
  description = "Routes resource ID."
  value       = criblio_routes.this.id
}

output "content_hash" {
  description = "Hash of the rendered routes config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id       = criblio_routes.this.id
    group_id = criblio_routes.this.group_id
    routes   = criblio_routes.this.routes
  }))
}
