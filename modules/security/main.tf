# Security module — security groups, IAM roles/profiles, and the SSM-stored
# Splunk admin password. Splunk- and Cribl-specific resources are gated on
# their respective enable_* toggles.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  splunk_enabled = var.enable_splunk ? 1 : 0
  cribl_enabled  = var.enable_cribl ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }
}

# --- NAT ------------------------------------------------------------------------

resource "aws_security_group" "nat_instance" {
  name        = "${var.environment}-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP egress (package downloads)"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS egress"
  }

  # NAT function: accept anything the private subnets send outbound.
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
    description = "Forwarded traffic from private subnets"
  }

  # SSH rule only exists when explicitly allowlisted; empty list = no SSH.
  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
      description = "SSH access (restricted)"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-nat-instance-sg"
  })
}

# --- Splunk ---------------------------------------------------------------------

resource "aws_security_group" "splunk" {
  count = local.splunk_enabled

  name        = "${var.environment}-splunk-sg"
  description = "Security group for Splunk instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.splunk_web_port
    to_port     = var.splunk_web_port
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
    description = "Splunk Web (VPC internal)"
  }

  ingress {
    from_port   = var.splunk_s2s_port
    to_port     = var.splunk_s2s_port
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
    description = "Splunk-to-Splunk forwarding (VPC internal)"
  }

  ingress {
    from_port   = var.splunk_management_port
    to_port     = var.splunk_management_port
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
    description = "Splunk management API (VPC internal)"
  }

  # Management from outside the VPC is always allowlist-only — deliberately
  # unaffected by allow_all_ips.
  dynamic "ingress" {
    for_each = length(var.management_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = var.splunk_management_port
      to_port     = var.splunk_management_port
      protocol    = "tcp"
      cidr_blocks = var.management_allowed_cidrs
      description = "Splunk management API (external, always restricted)"
    }
  }

  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.web_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = var.splunk_web_port
      to_port     = var.splunk_web_port
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.web_allowed_cidrs
      description = "Splunk Web (external access)"
    }
  }

  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.hec_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = var.splunk_hec_port
      to_port     = var.splunk_hec_port
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.hec_allowed_cidrs
      description = "Splunk HEC (HTTP Event Collector)"
    }
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
      description = "SSH access (restricted)"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All egress"
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-sg"
  })
}

# The Splunk admin password never appears in user_data or state-file plaintext
# paths the instance can read from disk — the instance retrieves it from this
# SecureString parameter at boot via its IAM role.
resource "aws_ssm_parameter" "splunk_admin_password" {
  count = local.splunk_enabled

  name        = "/${var.environment}/splunk/admin-password"
  description = "Splunk Enterprise admin password"
  type        = "SecureString"
  value       = var.splunk_admin_password

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-admin-password"
  })
}

resource "aws_iam_role" "splunk_instance" {
  count = local.splunk_enabled

  name = "${var.environment}-splunk-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-instance-role"
  })
}

# SSM Session Manager access plus read access to the admin-password parameter.
resource "aws_iam_role_policy" "splunk_instance" {
  count = local.splunk_enabled

  name = "${var.environment}-splunk-instance-policy"
  role = aws_iam_role.splunk_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = aws_ssm_parameter.splunk_admin_password[0].arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "splunk" {
  count = local.splunk_enabled

  name = "${var.environment}-splunk-instance-profile"
  role = aws_iam_role.splunk_instance[0].name

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-instance-profile"
  })
}

# --- Cribl ----------------------------------------------------------------------

# Self-referencing cluster SG: instances that carry it can talk to each other
# on any port (Splunk <-> Cribl Stream <-> Cribl Edge).
resource "aws_security_group" "internal" {
  count = local.cribl_enabled

  name        = "${var.environment}-internal-cluster-sg"
  description = "All ports open between Splunk, Cribl Stream, and Cribl Edge instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Intra-cluster traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All egress"
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-internal-cluster-sg"
  })
}

resource "aws_security_group" "cribl" {
  count = local.cribl_enabled

  name        = "${var.environment}-cribl-sg"
  description = "Security group for Cribl Stream and Edge instances"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.cribl_allowed_cidrs) > 0 ? {
      (tostring(var.cribl_web_port))  = "Cribl Web UI and leader/worker comms"
      (tostring(var.cribl_data_port)) = "Cribl data ingest"
    } : {}
    content {
      from_port   = tonumber(ingress.key)
      to_port     = tonumber(ingress.key)
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.cribl_allowed_cidrs
      description = ingress.value
    }
  }

  # RDP to the Windows Edge box is always allowlist-only — deliberately
  # unaffected by allow_all_ips.
  dynamic "ingress" {
    for_each = length(var.management_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = var.management_allowed_cidrs
      description = "RDP access (always restricted)"
    }
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
      description = "SSH access (restricted)"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All egress"
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-sg"
  })
}

resource "aws_iam_role" "cribl_instance" {
  count = local.cribl_enabled

  name = "${var.environment}-cribl-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-instance-role"
  })
}

# SSM Session Manager access only — Cribl instances get no S3 or other data
# permissions from this module.
resource "aws_iam_role_policy" "cribl_instance" {
  count = local.cribl_enabled

  name = "${var.environment}-cribl-instance-policy"
  role = aws_iam_role.cribl_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "cribl" {
  count = local.cribl_enabled

  name = "${var.environment}-cribl-instance-profile"
  role = aws_iam_role.cribl_instance[0].name

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-instance-profile"
  })
}
