# Tests for SmartStore S3 bucket security properties
#
# Verifies that the SmartStore S3 bucket has versioning enabled, server-side
# encryption (AES256), all public access blocked, and correct lifecycle
# tiering transitions and noncurrent expiration.
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

# --- Versioning is enabled ---

run "smartstore_bucket_versioning_enabled" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.smartstore.versioning_configuration[0].status == "Enabled"
    error_message = "SmartStore bucket versioning must be Enabled"
  }
}

# --- AES256 server-side encryption is configured ---

run "smartstore_bucket_uses_aes256_encryption" {
  command = plan

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.smartstore.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "SmartStore bucket must use AES256 server-side encryption"
  }
}

# --- All public access is blocked ---

run "smartstore_bucket_blocks_all_public_access" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.smartstore.block_public_acls == true
    error_message = "SmartStore bucket must have block_public_acls = true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.smartstore.block_public_policy == true
    error_message = "SmartStore bucket must have block_public_policy = true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.smartstore.ignore_public_acls == true
    error_message = "SmartStore bucket must have ignore_public_acls = true"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.smartstore.restrict_public_buckets == true
    error_message = "SmartStore bucket must have restrict_public_buckets = true"
  }
}

# --- Lifecycle transitions and noncurrent version expiration ---

run "smartstore_lifecycle_transitions_at_correct_thresholds" {
  command = plan

  assert {
    condition     = length([for t in aws_s3_bucket_lifecycle_configuration.smartstore.rule[0].transition : t if t.days == 30 && t.storage_class == "STANDARD_IA"]) > 0
    error_message = "SmartStore bucket must transition to STANDARD_IA at 30 days"
  }

  assert {
    condition     = length([for t in aws_s3_bucket_lifecycle_configuration.smartstore.rule[0].transition : t if t.days == 90 && t.storage_class == "GLACIER_IR"]) > 0
    error_message = "SmartStore bucket must transition to GLACIER_IR at 90 days"
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.smartstore.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "SmartStore bucket must expire noncurrent versions at 90 days"
  }
}
