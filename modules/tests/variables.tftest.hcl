# Tests for variables.tf - input variable validation
#
# Verifies that valid inputs are accepted and that the module interface
# exposes the expected variables with correct types and defaults.
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

# --- Positive test: valid default configuration passes plan ---

run "valid_default_configuration_passes" {
  command = plan

  assert {
    condition     = var.environment == "dev"
    error_message = "environment variable should be 'dev'"
  }
}

# --- VPC CIDR is set correctly ---

run "vpc_cidr_set_correctly" {
  command = plan

  assert {
    condition     = var.vpc_cidr == "10.0.0.0/16"
    error_message = "vpc_cidr should be '10.0.0.0/16', got ${var.vpc_cidr}"
  }
}

# --- Subnet counts match expected input ---

run "public_subnet_count_matches_input" {
  command = plan

  assert {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "expected 2 public subnet CIDRs, got ${length(var.public_subnet_cidrs)}"
  }
}

run "private_subnet_count_matches_input" {
  command = plan

  assert {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "expected 2 private subnet CIDRs, got ${length(var.private_subnet_cidrs)}"
  }
}

# --- Instance types are non-empty strings ---

run "nat_instance_type_is_non_empty" {
  command = plan

  assert {
    condition     = length(var.nat_instance_type) > 0
    error_message = "nat_instance_type must not be empty"
  }
}

run "splunk_instance_type_is_non_empty" {
  command = plan

  assert {
    condition     = length(var.splunk_instance_type) > 0
    error_message = "splunk_instance_type must not be empty"
  }
}

# --- Volume sizes are positive numbers ---

run "splunk_root_volume_size_is_positive" {
  command = plan

  assert {
    condition     = var.splunk_root_volume_size > 0
    error_message = "splunk_root_volume_size must be positive, got ${var.splunk_root_volume_size}"
  }
}

run "splunk_data_volume_size_is_positive" {
  command = plan

  assert {
    condition     = var.splunk_data_volume_size > 0
    error_message = "splunk_data_volume_size must be positive, got ${var.splunk_data_volume_size}"
  }
}

# --- Default volume sizes match documented cost assumptions ---
# Root: 20 GB, Data: 50 GB -> 70 GB total matches the README cost table

run "default_volume_sizes_match_cost_assumptions" {
  command = plan

  assert {
    condition     = var.splunk_root_volume_size == 20
    error_message = "default splunk_root_volume_size should be 20 GB, got ${var.splunk_root_volume_size}"
  }

  assert {
    condition     = var.splunk_data_volume_size == 50
    error_message = "default splunk_data_volume_size should be 50 GB, got ${var.splunk_data_volume_size}"
  }
}

# --- key_pair_name defaults to null (SSH disabled by default) ---

run "key_pair_name_defaults_to_null" {
  command = plan

  assert {
    condition     = var.key_pair_name == null
    error_message = "key_pair_name should default to null (SSH disabled by default)"
  }
}

# --- enable_cribl defaults to true ---

run "enable_cribl_defaults_to_true" {
  command = plan

  assert {
    condition     = var.enable_cribl == true
    error_message = "enable_cribl should default to true"
  }
}

# --- Cribl instance type defaults ---

run "cribl_stream_instance_type_default" {
  command = plan

  assert {
    condition     = var.cribl_stream_instance_type == "t3a.small"
    error_message = "cribl_stream_instance_type should default to t3a.small, got ${var.cribl_stream_instance_type}"
  }
}

run "cribl_edge_instance_type_default" {
  command = plan

  assert {
    condition     = var.cribl_edge_instance_type == "t3a.medium"
    error_message = "cribl_edge_instance_type should default to t3a.medium, got ${var.cribl_edge_instance_type}"
  }
}

# --- management_allowed_cidrs defaults to empty ---

run "management_allowed_cidrs_default" {
  command = plan

  assert {
    condition     = length(var.management_allowed_cidrs) == 0
    error_message = "management_allowed_cidrs should default to []"
  }
}

# --- cribl_allowed_cidrs defaults to empty ---

run "cribl_allowed_cidrs_default" {
  command = plan

  assert {
    condition     = length(var.cribl_allowed_cidrs) == 0
    error_message = "cribl_allowed_cidrs should default to []"
  }
}
