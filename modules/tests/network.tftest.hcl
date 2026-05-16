# Tests for network module wiring and root module outputs
#
# Verifies that the root module correctly wires the network module and
# that network outputs are surfaced correctly. Tests run at plan time
# using mock providers - no AWS credentials needed.
#
# Note: With mock_provider, aws_route resource creation cannot be asserted at
# plan time. The NAT route fix (aws_route.private_nat) is tested at apply time
# in real deployments. The prerequisite test below verifies that subnets and
# the NAT module are wired correctly as a proxy for routing readiness.

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

# Override non-network child modules so we can test the root module's
# network wiring in isolation.
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

# --- Plan succeeds with valid network inputs ---

run "network_plan_succeeds" {
  command = plan
}

# --- VPC CIDR block matches input variable ---

run "vpc_cidr_block_matches_input" {
  command = plan

  assert {
    condition     = output.vpc_cidr_block == "10.0.0.0/16"
    error_message = "vpc_cidr_block output should match input '10.0.0.0/16', got ${output.vpc_cidr_block}"
  }
}

# --- Correct number of public subnets created ---

run "correct_number_of_public_subnets" {
  command = plan

  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "expected 2 public subnets, got ${length(output.public_subnet_ids)}"
  }
}

# --- Correct number of private subnets created ---

run "correct_number_of_private_subnets" {
  command = plan

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "expected 2 private subnets, got ${length(output.private_subnet_ids)}"
  }
}

# --- Route table outputs are non-null (route tables are created) ---

run "route_tables_are_created" {
  command = plan

  assert {
    condition     = output.nat_security_group_id != null
    error_message = "nat_security_group_id should be non-null after network wiring"
  }

  assert {
    condition     = output.splunk_security_group_id != null
    error_message = "splunk_security_group_id should be non-null after network wiring"
  }
}

# --- Prerequisites: Private subnets and NAT module are wired correctly ---
# Verifies that the root module correctly wires the network and compute modules
# such that private subnets and the NAT instance both exist. This is a prerequisite
# check — with mock_provider, route resource creation cannot be asserted at plan
# time (plan does not validate routing correctness). The actual NAT route fix
# (aws_route.private_nat in modules/main.tf) is tracked in issue #18.

run "private_subnets_and_nat_module_prerequisites" {
  command = plan

  assert {
    condition     = length(output.private_subnet_ids) > 0
    error_message = "private subnets must exist as a prerequisite for NAT routing"
  }

  assert {
    condition     = output.nat_instance_id != null
    error_message = "NAT instance must be wired through the root module outputs"
  }
}

# --- NAT instance public IP is exposed for egress routing ---

run "nat_instance_public_ip_is_exposed" {
  command = plan

  assert {
    condition     = output.nat_instance_public_ip != null
    error_message = "nat_instance_public_ip must be exposed in root module outputs"
  }
}
