output "id" {
  description = "Worker group ID for cross-module wiring."
  value       = criblio_group.this.id
}

output "content_hash" {
  description = "Hash of the rendered group config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id          = criblio_group.this.id
    name        = criblio_group.this.name
    description = criblio_group.this.description
    product     = criblio_group.this.product
    on_prem     = criblio_group.this.on_prem
    streamtags  = criblio_group.this.streamtags
  }))
}
