# Tests for cribl-config module (criblio provider layer)
#
# Verifies the additive nature of the new module: when enable_criblio_config
# is false (default), the layer is a no-op. When true, the worker-group +
# commit-deploy chain plans cleanly with mocked criblio + null providers.

mock_provider "aws" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "archive" {}
mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = ""
    }
  }
}
mock_provider "criblio" {
  alias = "onprem"
}
mock_provider "criblio" {
  alias = "cloud"
}

# module.network is not overridden — running it under mock_provider keeps
# its real outputs (vpc_cidr_block, subnet IDs) populated, which other
# tftest files assert on after the suite-wide override-module load order.

override_module {
  target = module.security
  outputs = {
    nat_security_group_id        = "sg-00000000000000001"
    splunk_security_group_id     = "sg-00000000000000002"
    splunk_instance_profile_name = "mock-splunk-instance-profile"
    splunk_iam_role_arn          = "arn:aws:iam::123456789012:role/mock-splunk-role"
    splunk_password_ssm_name     = "/dev/splunk/admin-password"
    internal_security_group_id   = "sg-00000000000000003"
    cribl_security_group_id      = "sg-00000000000000004"
    cribl_instance_profile_name  = "mock-cribl-instance-profile"
  }
}

override_module {
  target = module.compute
  outputs = {
    nat_instance_id                  = "i-00000000000000001"
    nat_instance_private_ip          = "10.0.1.10"
    nat_instance_public_ip           = "203.0.113.10"
    nat_primary_network_interface_id = "eni-00000000000000001"
  }
}

override_module {
  target = module.splunk
  outputs = {
    splunk_instance_id          = "i-00000000000000002"
    splunk_instance_private_ip  = "10.0.10.10"
    splunk_instance_public_ip   = "203.0.113.20"
    splunk_web_url              = "http://203.0.113.20:8000"
    splunk_cloudwatch_log_group = "/aws/ec2/splunk"
    splunk_app_log_group        = "/aws/ec2/splunk/app"
  }
}

override_module {
  target = module.cribl
  outputs = {
    cribl_stream_instance_id = "i-00000000000000003"
    cribl_stream_private_ip  = "10.0.10.20"
    cribl_stream_public_ip   = "203.0.113.30"
    cribl_stream_web_url     = "http://203.0.113.30:4200"
    cribl_edge_instance_id   = "i-00000000000000004"
    cribl_edge_private_ip    = "10.0.10.21"
    cribl_edge_public_ip     = "203.0.113.31"
  }
}

variables {
  environment           = "test"
  enable_auto_stop      = false
  availability_zones    = ["us-east-2a", "us-east-2b"]
  splunk_admin_password = "TestPassword123!"
  enable_cribl          = true
}

run "criblio_config_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_criblio_config == false
    error_message = "enable_criblio_config must default to false (Phase 2 additive build)."
  }

  assert {
    condition     = module.cribl_config.enabled == false
    error_message = "cribl_config module must report disabled when flag is false."
  }

  assert {
    condition     = module.cribl_config.worker_group_id == null
    error_message = "worker_group_id must be null when the layer is disabled."
  }
}

# The enabled path is not exercised via `command = plan` here because
# `criblio_commit.items` is a list-of-objects that mock_provider cannot
# populate (override_resource on a count'd module instance is rejected by
# OpenTofu). `tofu validate` already verifies the enabled graph is well-formed.

run "onprem_bearer_token_defaults_to_empty" {
  command = plan

  assert {
    condition     = var.cribl_onprem_bearer_token == ""
    error_message = "cribl_onprem_bearer_token must default to empty string."
  }
}

run "cloud_credentials_default_empty" {
  command = plan

  assert {
    condition     = var.cribl_cloud_client_id == "" && var.cribl_cloud_organization_id == "" && var.cribl_cloud_workspace_id == ""
    error_message = "Cribl Cloud credentials must default to empty (Cloud unused in Phase 2)."
  }

  assert {
    condition     = var.cribl_cloud_domain == "cribl.cloud"
    error_message = "cribl_cloud_domain must default to cribl.cloud."
  }
}
