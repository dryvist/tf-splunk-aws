terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.23.36"
    }
  }
}

# Polymorphic resource: caller passes exactly one of input_http / input_tcp /
# input_syslog / input_splunk_hec / etc. Unset blocks are omitted via the
# Terraform null-attribute pattern.

resource "criblio_source" "this" {
  id       = var.source_id
  group_id = var.group_id

  input_http       = var.input_http
  input_tcp        = var.input_tcp
  input_syslog     = var.input_syslog
  input_splunk_hec = var.input_splunk_hec
}
