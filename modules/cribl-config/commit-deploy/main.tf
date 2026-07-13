# Commit + deploy chokepoint for the criblio config layer.
#
# The criblio provider exposes commit and deploy as native resources. The
# `terraform_data` trigger forces criblio_commit to be replaced whenever any
# upstream module's content_hash changes, which produces a fresh commit and
# in turn a fresh deploy. Provider 1.25.1 no longer exports the created
# commit's hash on criblio_commit, so the deploy reads the group's version
# list through the criblio_config_version data source instead; depends_on
# defers that read until after the commit lands, and items[0] is the newest
# commit (the API returns git-log order).
#
# No local-exec, no shell, no inline script — pure HCL.

terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source  = "criblio/criblio"
      version = "1.25.2"
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

data "criblio_config_version" "post_commit" {
  id         = var.worker_group_id
  depends_on = [criblio_commit.this]
}

resource "criblio_deploy" "this" {
  id      = var.worker_group_id
  version = data.criblio_config_version.post_commit.items[0]
}
