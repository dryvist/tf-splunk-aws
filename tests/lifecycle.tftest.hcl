# Tests for the auto-stop lifecycle guardrail (modules/lifecycle)
#
# Verifies that the enable_auto_stop flag and stop_schedule_expression variable have
# correct defaults, and that the root module plans successfully with the guardrail
# both disabled and enabled. All runs use mock providers - no AWS credentials needed.

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

# Override the lifecycle module so the root plan resolves without evaluating its
# scheduler resources: the mock AWS provider yields a non-ARN string that the
# aws_scheduler_schedule "role_arn" attribute rejects at plan time. Consistent with
# the other child-module overrides above; the real role ARNs are produced at apply.
override_module {
  target = module.lifecycle
  outputs = {
    uptime_sweep_function_name   = "dev-splunk-aws-uptime-sweep"
    uptime_sweep_schedule_name   = "dev-splunk-aws-uptime-sweep"
    scheduled_stop_schedule_name = null
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

# --- Guardrail defaults: uptime sweep on, fixed schedule off ---

run "auto_stop_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_auto_stop == true
    error_message = "enable_auto_stop must default to true — the uptime sweep is the primary cost control"
  }
}

run "max_runtime_hours_defaults_to_24" {
  command = plan

  assert {
    condition     = var.max_runtime_hours == 24
    error_message = "max_runtime_hours must default to 24, got ${var.max_runtime_hours}"
  }
}

run "scheduled_stop_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_scheduled_stop == false
    error_message = "enable_scheduled_stop must default to false — the uptime sweep is usually sufficient"
  }
}

# --- stop_schedule_expression defaults to nightly cron ---

run "stop_schedule_expression_default" {
  command = plan

  assert {
    condition     = var.stop_schedule_expression == "cron(0 8 * * ? *)"
    error_message = "stop_schedule_expression must default to nightly cron, got ${var.stop_schedule_expression}"
  }
}

# --- Plan succeeds with all guardrails disabled ---

run "auto_stop_disabled_plan_succeeds" {
  command = plan

  variables {
    enable_auto_stop      = false
    enable_scheduled_stop = false
  }
}

# --- Plan succeeds with the uptime sweep enabled (default) ---

run "auto_stop_enabled_plan_succeeds" {
  command = plan

  variables {
    enable_auto_stop  = true
    max_runtime_hours = 48
  }
}

# --- Plan succeeds with the fixed-schedule stop enabled ---

run "scheduled_stop_plan_succeeds" {
  command = plan

  variables {
    enable_scheduled_stop    = true
    stop_schedule_expression = "rate(48 hours)"
  }
}
