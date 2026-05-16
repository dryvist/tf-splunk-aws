# Security Module - Security Groups and IAM
# Handles all security-related resources for Splunk AWS deployment

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Local values for consistent tagging
locals {
  common_tags = {
    Environment = var.environment
    Project     = "splunk-aws"
    ManagedBy   = "terraform"
  }
}

# NAT Instance Security Group
resource "aws_security_group" "nat_instance" {
  name        = "${var.environment}-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = var.vpc_id

  # Allow HTTP outbound
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS outbound
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from private subnets (for NAT functionality)
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # SSH access (restricted to explicit CIDRs — empty list disables SSH entirely)
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

# Splunk Security Group
resource "aws_security_group" "splunk" {
  name        = "${var.environment}-splunk-sg"
  description = "Security group for Splunk instances"
  vpc_id      = var.vpc_id

  # Splunk Web (8000)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
  }

  # Splunk Forwarder (9997)
  ingress {
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
  }

  # Splunk Management (8089) — VPC internal
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
  }

  # Splunk Management (8089) — external restricted access
  dynamic "ingress" {
    for_each = length(var.management_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 8089
      to_port     = 8089
      protocol    = "tcp"
      cidr_blocks = var.management_allowed_cidrs
      description = "Splunk mgmt (external, always restricted)"
    }
  }

  # Splunk Web (8000) from external CIDRs - only created when web_allowed_cidrs is non-empty or allow_all_ips
  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.web_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 8000
      to_port     = 8000
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.web_allowed_cidrs
      description = "Splunk Web (external access)"
    }
  }

  # Splunk HEC (8088) - only created when hec_allowed_cidrs is non-empty or allow_all_ips
  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.hec_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 8088
      to_port     = 8088
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.hec_allowed_cidrs
      description = "Splunk HEC (HTTP Event Collector)"
    }
  }

  # SSH access (restricted to explicit CIDRs — empty list disables SSH entirely)
  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
      description = "SSH from allowed CIDRs (when SSH enabled)"
    }
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-sg"
  })
}

# SSM Parameter Store - Splunk admin password (SecureString)
resource "aws_ssm_parameter" "splunk_admin_password" {
  name        = "/${var.environment}/splunk/admin-password"
  description = "Splunk Enterprise admin password"
  type        = "SecureString"
  value       = var.splunk_admin_password

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-admin-password"
  })
}

# IAM Role for Splunk Instance
resource "aws_iam_role" "splunk_instance" {
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

# IAM Policy for Splunk Instance (basic EC2 and SSM access)
resource "aws_iam_role_policy" "splunk_instance" {
  name = "${var.environment}-splunk-instance-policy"
  role = aws_iam_role.splunk_instance.id

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
        Resource = aws_ssm_parameter.splunk_admin_password.arn
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

# IAM Instance Profile for Splunk
resource "aws_iam_instance_profile" "splunk" {
  name = "${var.environment}-splunk-instance-profile"
  role = aws_iam_role.splunk_instance.name

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-instance-profile"
  })
}

# Internal Cluster Security Group — self-referencing, all VMs fully open to each other
resource "aws_security_group" "internal" {
  count = var.enable_cribl ? 1 : 0

  name        = "${var.environment}-internal-cluster-sg"
  description = "All ports open between Splunk, Cribl Stream, and Cribl Edge instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-internal-cluster-sg"
  })
}

# Cribl Security Group — external access to Cribl ports
resource "aws_security_group" "cribl" {
  count = var.enable_cribl ? 1 : 0

  name        = "${var.environment}-cribl-sg"
  description = "Security group for Cribl Stream and Edge instances"
  vpc_id      = var.vpc_id

  # Cribl ports (4200: Web UI + leader/worker comms; 9997: data ingest)
  dynamic "ingress" {
    for_each = var.allow_all_ips || length(var.cribl_allowed_cidrs) > 0 ? {
      "4200" = "Cribl Web UI and leader/worker comms"
      "9997" = "Cribl data ingest"
    } : {}
    content {
      from_port   = tonumber(ingress.key)
      to_port     = tonumber(ingress.key)
      protocol    = "tcp"
      cidr_blocks = var.allow_all_ips ? ["0.0.0.0/0"] : var.cribl_allowed_cidrs
      description = ingress.value
    }
  }

  # RDP (3389) — always restricted to management CIDRs
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

  # SSH (22) — same pattern as existing instances
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
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-sg"
  })
}

# IAM Role for Cribl Instances
resource "aws_iam_role" "cribl_instance" {
  count = var.enable_cribl ? 1 : 0

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

# IAM Policy for Cribl Instances (SSM management only — no module-managed S3 access)
resource "aws_iam_role_policy" "cribl_instance" {
  count = var.enable_cribl ? 1 : 0

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

# IAM Instance Profile for Cribl
resource "aws_iam_instance_profile" "cribl" {
  count = var.enable_cribl ? 1 : 0

  name = "${var.environment}-cribl-instance-profile"
  role = aws_iam_role.cribl_instance[0].name

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-instance-profile"
  })
}
