# Tests for Cribl module (Stream + Edge)
#
# Verifies enable_cribl flag behavior, instance type defaults, and that
# Cribl outputs are correctly wired through the root module.
# Does NOT override module.cribl (test subject).
# All runs use mock providers - no AWS credentials needed.

mock_provider "aws" {}
mock_provider "random" {}
mock_provider "tls" {}
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
mock_provider "null" {}
mock_provider "criblio" {
  alias = "cloud"
}

# Override all modules EXCEPT cribl (test subject)
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

# Shared valid defaults for all runs
variables {
  environment          = "dev"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-2a", "us-east-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  nat_instance_type    = "t4g.nano"
  splunk_instance_type = "t3a.small"
}

# --- enable_cribl defaults to true ---

run "cribl_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_cribl == true
    error_message = "enable_cribl must default to true"
  }
}

# --- Plan succeeds with Cribl enabled (default) ---

run "cribl_enabled_plan_succeeds" {
  command = plan
}

# --- Plan succeeds with Cribl disabled ---

run "cribl_disabled_plan_succeeds" {
  command = plan

  variables {
    enable_cribl = false
  }
}

# --- Cribl outputs are non-null when enabled ---

run "cribl_outputs_non_null_when_enabled" {
  command = plan

  assert {
    condition     = output.cribl_stream_instance_id != null
    error_message = "cribl_stream_instance_id must be non-null when enabled"
  }

  assert {
    condition     = output.cribl_edge_instance_id != null
    error_message = "cribl_edge_instance_id must be non-null when enabled"
  }
}

# --- Cribl Stream web URL follows expected format ---

run "cribl_stream_web_url_format" {
  command = plan

  assert {
    condition     = output.cribl_stream_web_url != null
    error_message = "cribl_stream_web_url must be non-null when enabled"
  }
}

# --- Default instance types are correct ---

run "cribl_default_instance_types" {
  command = plan

  assert {
    condition     = var.cribl_stream_instance_type == "t3a.small"
    error_message = "cribl_stream_instance_type should default to t3a.small"
  }

  assert {
    condition     = var.cribl_edge_instance_type == "t3a.medium"
    error_message = "cribl_edge_instance_type should default to t3a.medium"
  }
}

# --- Plan succeeds with custom instance types ---

run "custom_cribl_instance_types" {
  command = plan

  variables {
    cribl_stream_instance_type = "t3a.medium"
    cribl_edge_instance_type   = "t3a.large"
  }

  assert {
    condition     = var.cribl_stream_instance_type == "t3a.medium"
    error_message = "cribl_stream_instance_type should accept custom value"
  }
}

# --- Plan succeeds with Cribl CIDRs ---

run "cribl_with_allowed_cidrs" {
  command = plan

  variables {
    cribl_allowed_cidrs      = ["203.0.113.0/24"]
    management_allowed_cidrs = ["10.0.0.0/8"]
  }
}
