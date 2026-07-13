# Cribl-as-Code config layer.
#
# Sits on top of modules/cribl/ (EC2 Stream leader). Provides declarative
# management of Cribl objects (worker groups, packs, pipelines, routes,
# sources, destinations) via the official criblio Terraform provider.
#
# Gated by var.enable_criblio_config; default false. When false, every
# resource in this module and its submodules is count = 0.
#
# Provider auth:
#   - criblio.onprem (default alias): reads CRIBL_ONPREM_SERVER_URL and
#     CRIBL_BEARER_TOKEN from env (or var.onprem_server_url / var.onprem_bearer_token
#     when provided)
#   - criblio.cloud: OAuth2 client credentials for Cribl.Cloud workspaces
#     (declared but unused until a workspace is provisioned)

terraform {
  required_version = ">= 1.6"
  required_providers {
    criblio = {
      source                = "criblio/criblio"
      version               = "1.25.2"
      configuration_aliases = [criblio.onprem, criblio.cloud]
    }
  }
}

locals {
  enabled = var.enable_criblio_config
}

module "worker_group" {
  source = "./worker-group"
  count  = local.enabled ? 1 : 0

  group_id    = var.default_worker_group_id
  description = "Default Stream worker group managed by tf-splunk-aws"
  product     = "stream"
  on_prem     = true
  streamtags  = [var.environment, "tf-managed"]

  providers = {
    criblio = criblio.onprem
  }
}

module "commit_deploy" {
  source = "./commit-deploy"
  count  = local.enabled ? 1 : 0

  worker_group_id = module.worker_group[0].id

  # Re-deploy whenever any managed object's content hash changes.
  triggers = {
    worker_group = module.worker_group[0].content_hash
  }

  providers = {
    criblio = criblio.onprem
  }
}
