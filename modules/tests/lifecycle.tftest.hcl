# Tests for auto-lifecycle management
#
# Verifies that the enable_auto_lifecycle flag, auto_shutdown_minutes, and
# lifecycle_interval_hours variables have correct defaults, and that the
# module plans successfully with lifecycle both disabled and enabled.
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
mock_provider "criblio" {
  alias = "cloud"
}

# Override child modules so the root module output expressions resolve at plan time.
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
}

# --- enable_auto_lifecycle defaults to false ---

run "auto_lifecycle_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_auto_lifecycle == false
    error_message = "enable_auto_lifecycle must default to false"
  }
}

# --- auto_shutdown_minutes defaults to 60 ---

run "auto_shutdown_minutes_default_is_60" {
  command = plan

  assert {
    condition     = var.auto_shutdown_minutes == 60
    error_message = "auto_shutdown_minutes must default to 60, got ${var.auto_shutdown_minutes}"
  }
}

# --- lifecycle_interval_hours defaults to 4 ---

run "lifecycle_interval_hours_default_is_4" {
  command = plan

  assert {
    condition     = var.lifecycle_interval_hours == 4
    error_message = "lifecycle_interval_hours must default to 4, got ${var.lifecycle_interval_hours}"
  }
}

# --- Plan succeeds with lifecycle disabled (default) ---

run "lifecycle_disabled_plan_succeeds" {
  command = plan

  variables {
    enable_auto_lifecycle = false
  }
}

# --- Plan succeeds with lifecycle enabled ---

run "lifecycle_enabled_plan_succeeds" {
  command = plan

  variables {
    enable_auto_lifecycle = true
  }
}

# --- Plan succeeds with custom lifecycle parameters ---

run "custom_lifecycle_parameters_plan_succeeds" {
  command = plan

  variables {
    enable_auto_lifecycle    = true
    auto_shutdown_minutes    = 90
    lifecycle_interval_hours = 6
  }
}
