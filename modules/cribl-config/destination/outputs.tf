output "id" {
  description = "Destination ID."
  value       = criblio_destination.this.id
}

output "content_hash" {
  description = "Hash of the rendered destination config; feeds commit-deploy triggers."
  value = sha256(jsonencode({
    id                = criblio_destination.this.id
    group_id          = criblio_destination.this.group_id
    output_s3         = criblio_destination.this.output_s3
    output_splunk_hec = criblio_destination.this.output_splunk_hec
    output_kafka      = criblio_destination.this.output_kafka
    output_syslog     = criblio_destination.this.output_syslog
  }))
}
