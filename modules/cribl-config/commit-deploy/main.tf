# Commit + deploy chokepoint for the criblio config layer.
#
# The criblio provider exposes commit and deploy as native resources. The
# `terraform_data` trigger forces criblio_commit to be replaced whenever any
# upstream module's content_hash changes, which produces a fresh commit and
# in turn a fresh deploy (the deploy depends on the commit's version output).
#
# No local-exec, no shell, no inline script — pure HCL.

terraform {
  required_version = ">= 1.0"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.23.36"
    }
  }
}

resource "terraform_data" "trigger" {
  input = var.triggers
}

resource "criblio_commit" "this" {
  group   = var.worker_group_id
  message = "tf-splunk-aws: tofu apply"

  lifecycle {
    replace_triggered_by = [terraform_data.trigger]
  }
}

resource "criblio_deploy" "this" {
  id      = var.worker_group_id
  version = criblio_commit.this.items[0].commit
}
