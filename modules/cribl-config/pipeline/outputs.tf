output "id" {
  description = "Pipeline ID."
  value       = criblio_pipeline.this.id
}

output "content_hash" {
  description = "Hash of the rendered pipeline config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id       = criblio_pipeline.this.id
    group_id = criblio_pipeline.this.group_id
    conf     = criblio_pipeline.this.conf
  }))
}
