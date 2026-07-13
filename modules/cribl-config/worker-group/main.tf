terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.25.2"
    }
  }
}

resource "criblio_group" "this" {
  id          = var.group_id
  name        = var.name != "" ? var.name : var.group_id
  description = var.description
  product     = var.product
  on_prem     = var.on_prem
  streamtags  = var.streamtags
}
