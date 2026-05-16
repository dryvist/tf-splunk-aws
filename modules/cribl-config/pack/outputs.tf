output "id" {
  description = "Pack ID."
  value       = criblio_pack.this.id
}

output "content_hash" {
  description = "Hash of the rendered pack config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id       = criblio_pack.this.id
    group_id = criblio_pack.this.group_id
    source   = criblio_pack.this.source
    filename = criblio_pack.this.filename
    spec     = criblio_pack.this.spec
    tags     = criblio_pack.this.tags
  }))
}
