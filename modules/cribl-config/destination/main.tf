terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.25.1"
    }
  }
}

resource "criblio_destination" "this" {
  id       = var.destination_id
  group_id = var.group_id

  output_s3         = var.output_s3
  output_splunk_hec = var.output_splunk_hec
  output_kafka      = var.output_kafka
  output_syslog     = var.output_syslog
}
