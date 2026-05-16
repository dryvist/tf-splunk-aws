terraform {
  required_version = ">= 1.0"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.23.32"
    }
  }
}

resource "criblio_routes" "this" {
  id       = var.routes_id
  group_id = var.group_id
  routes   = var.routes
}
