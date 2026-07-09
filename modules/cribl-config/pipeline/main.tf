terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.25.1"
    }
  }
}

resource "criblio_pipeline" "this" {
  id       = var.pipeline_id
  group_id = var.group_id

  conf = {
    description        = var.description
    async_func_timeout = var.async_func_timeout
    output             = var.output_destination
    streamtags         = var.streamtags
    functions          = var.functions
  }
}
