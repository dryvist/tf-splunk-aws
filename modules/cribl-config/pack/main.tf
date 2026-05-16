terraform {
  required_version = ">= 1.0"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.23.32"
    }
  }
}

resource "criblio_pack" "this" {
  id       = var.pack_id
  group_id = var.group_id
  source   = var.source_url != "" ? var.source_url : null
  filename = var.filename != "" ? var.filename : null
  spec     = var.spec
  tags     = var.tags
}
