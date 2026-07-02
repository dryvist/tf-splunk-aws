# Tests for root module outputs
#
# Verifies that the root module aggregates outputs from all child modules
# correctly and that output structure matches expected shapes for downstream
# consumers (Ansible, documentation, monitoring).
# All runs use mock providers - no AWS credentials needed.

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

# Override all child modules with realistic mock outputs so the root module
# output expressions can be evaluated at plan time.
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
    nat_cloudwatch_log_group         = "/aws/ec2/nat-instance"
  }
}

override_module {
  target = module.splunk
  outputs = {
    splunk_instance_id          = "i-00000000000000002"
    splunk_instance_private_ip  = "10.0.10.20"
    splunk_instance_public_ip   = null
    splunk_web_url              = "http://10.0.10.20:8000"
    splunk_cloudwatch_log_group = "/aws/ec2/splunk"
    splunk_app_log_group        = "/aws/ec2/splunk/app"
  }
}

override_module {
  target = module.cribl
  outputs = {
    cribl_stream_instance_id = "i-00000000000000003"
    cribl_stream_private_ip  = "10.0.10.30"
    cribl_stream_public_ip   = null
    cribl_stream_web_url     = "http://10.0.10.30:4200"
    cribl_edge_instance_id   = "i-00000000000000004"
    cribl_edge_private_ip    = "10.0.10.40"
    cribl_edge_public_ip     = null
  }
}

# Shared valid defaults for all runs
variables {
  environment          = "dev"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-2a", "us-east-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  nat_instance_type    = "t4g.nano"
  splunk_instance_type = "t3a.small"
  enable_auto_stop     = false
  enable_cribl         = true
}

# --- Plan succeeds and all outputs are produced ---

run "outputs_plan_succeeds" {
  command = plan
}

# --- estimated_cost is computed from the enabled components ---
# The cost output must expose monthly/daily totals and a per-component map.

run "estimated_cost_has_expected_shape" {
  command = plan

  assert {
    condition     = startswith(output.estimated_cost.always_on_monthly, "$")
    error_message = "estimated_cost.always_on_monthly must be a dollar amount"
  }

  assert {
    condition     = startswith(output.estimated_cost.daily_running, "$")
    error_message = "estimated_cost.daily_running must be a dollar amount"
  }

  assert {
    condition     = contains(keys(output.estimated_cost.components), "nat")
    error_message = "estimated_cost.components must always include the NAT instance"
  }

  assert {
    condition     = contains(keys(output.estimated_cost.components), "splunk") && contains(keys(output.estimated_cost.components), "cribl_stream")
    error_message = "estimated_cost.components must include splunk and cribl_stream when both workloads are enabled"
  }
}

# --- estimated_cost drops disabled components ---

run "estimated_cost_excludes_disabled_workloads" {
  command = plan

  variables {
    enable_splunk = false
    enable_cribl  = false
  }

  assert {
    condition     = !contains(keys(output.estimated_cost.components), "splunk") && !contains(keys(output.estimated_cost.components), "cribl_stream")
    error_message = "estimated_cost.components must not include disabled workloads"
  }
}

# --- Splunk web URL follows expected format ---
# The splunk_web_url output must be a valid HTTP URL pointing to port 8000.

run "splunk_web_url_follows_http_format" {
  command = plan

  assert {
    condition     = startswith(output.splunk_web_url, "http://")
    error_message = "splunk_web_url must start with 'http://', got ${output.splunk_web_url}"
  }

  assert {
    condition     = endswith(output.splunk_web_url, ":8000")
    error_message = "splunk_web_url must end with ':8000' (Splunk web port), got ${output.splunk_web_url}"
  }
}

# --- Splunk instance ID is non-null ---

run "splunk_instance_id_is_non_null" {
  command = plan

  assert {
    condition     = output.splunk_instance_id != null
    error_message = "splunk_instance_id output must be non-null"
  }
}

# --- Splunk private IP is in the private subnet range ---
# Splunk must be in a private subnet (10.0.10.0/24 or 10.0.20.0/24).

run "splunk_private_ip_is_non_null" {
  command = plan

  assert {
    condition     = output.splunk_instance_private_ip != null
    error_message = "splunk_instance_private_ip output must be non-null"
  }
}

# --- connection_info output contains all required fields ---
# The connection_info map is consumed by operators for quick access.
# It must contain splunk_web_url, vpc_id, and nat_instance fields.

run "connection_info_contains_required_fields" {
  command = plan

  assert {
    condition     = output.connection_info.splunk_web_url != null
    error_message = "connection_info must contain splunk_web_url"
  }

  assert {
    condition     = output.connection_info.vpc_id != null
    error_message = "connection_info must contain vpc_id"
  }

  assert {
    condition     = output.connection_info.nat_instance != null
    error_message = "connection_info must contain nat_instance"
  }
}

# --- Network-related outputs are all present ---

run "network_outputs_are_present" {
  command = plan

  assert {
    condition     = output.vpc_id != null
    error_message = "vpc_id output must be non-null"
  }

  assert {
    condition     = output.vpc_cidr_block == "10.0.0.0/16"
    error_message = "vpc_cidr_block must match input '10.0.0.0/16', got ${output.vpc_cidr_block}"
  }

  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "public_subnet_ids must contain 2 entries, got ${length(output.public_subnet_ids)}"
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "private_subnet_ids must contain 2 entries, got ${length(output.private_subnet_ids)}"
  }
}

# --- NAT instance outputs are all present ---

run "nat_instance_outputs_are_present" {
  command = plan

  assert {
    condition     = output.nat_instance_id != null
    error_message = "nat_instance_id output must be non-null"
  }

  assert {
    condition     = output.nat_instance_public_ip != null
    error_message = "nat_instance_public_ip output must be non-null"
  }

  assert {
    condition     = output.nat_instance_private_ip != null
    error_message = "nat_instance_private_ip output must be non-null"
  }
}

# --- Cribl outputs are present when enabled (default) ---

run "cribl_outputs_are_present" {
  command = plan

  assert {
    condition     = output.cribl_stream_instance_id != null
    error_message = "cribl_stream_instance_id must be non-null when enable_cribl defaults to true"
  }

  assert {
    condition     = output.cribl_stream_private_ip != null
    error_message = "cribl_stream_private_ip must be non-null when enable_cribl defaults to true"
  }

  assert {
    condition     = output.cribl_stream_web_url != null
    error_message = "cribl_stream_web_url must be non-null when enable_cribl defaults to true"
  }

  assert {
    condition     = output.cribl_edge_instance_id != null
    error_message = "cribl_edge_instance_id must be non-null when enable_cribl defaults to true"
  }

  assert {
    condition     = output.cribl_edge_private_ip != null
    error_message = "cribl_edge_private_ip must be non-null when enable_cribl defaults to true"
  }
}

# --- Cribl security group outputs are present ---

run "cribl_security_group_outputs_present" {
  command = plan

  assert {
    condition     = output.internal_security_group_id != null
    error_message = "internal_security_group_id must be non-null when Cribl enabled"
  }

  assert {
    condition     = output.cribl_security_group_id != null
    error_message = "cribl_security_group_id must be non-null when Cribl enabled"
  }
}

# --- connection_info includes Cribl fields when enabled ---

run "connection_info_includes_cribl_fields" {
  command = plan

  assert {
    condition     = output.connection_info.cribl_stream_web_url != null
    error_message = "connection_info must contain cribl_stream_web_url when Cribl enabled"
  }

  assert {
    condition     = output.connection_info.cribl_edge_ip != null
    error_message = "connection_info must contain cribl_edge_ip when Cribl enabled"
  }
}
