output "id" {
  description = "Source ID."
  value       = criblio_source.this.id
}

output "content_hash" {
  description = "Hash of the rendered source config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id               = criblio_source.this.id
    group_id         = criblio_source.this.group_id
    input_http       = criblio_source.this.input_http
    input_tcp        = criblio_source.this.input_tcp
    input_syslog     = criblio_source.this.input_syslog
    input_splunk_hec = criblio_source.this.input_splunk_hec
  }))
}
