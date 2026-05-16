# Splunk Module - Splunk-specific instances and configuration
# Handles Splunk infrastructure deployment and configuration

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

# Current AWS region (used in user_data for SSM parameter retrieval)
data "aws_region" "current" {}

# Local values for consistent tagging
locals {
  common_tags = {
    Environment = var.environment
    Project     = "splunk-aws"
    ManagedBy   = "terraform"
  }
  # rate() requires singular "hour" for value 1, plural "hours" for all others
  lifecycle_schedule_unit = var.lifecycle_interval_hours == 1 ? "hour" : "hours"

  # Download URL — validated at plan/apply time via data "http"
  splunk_pkg_url = "https://download.splunk.com/products/splunk/releases/${var.splunk_version}/linux/splunk-${var.splunk_version}-${var.splunk_build}-linux-amd64.tgz"
}

# Pre-deployment validation: verify Splunk download URL exists
data "http" "splunk_pkg" {
  url    = local.splunk_pkg_url
  method = "HEAD"
}

# User data script for Splunk instance
locals {
  splunk_user_data = base64encode(<<-EOF
    #!/bin/bash
    set -eo pipefail
    yum update -y

    # Install required packages
    yum install -y wget tar

    # Install SSM agent (should be pre-installed on Amazon Linux 2)
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Install CloudWatch agent
    yum install -y amazon-cloudwatch-agent

    # Mount the dedicated EBS data volume at /opt/splunk before installing Splunk.
    # The instance attaches a gp3 volume at /dev/sdf (variable: splunk_data_volume_size).
    # Without mounting, Splunk writes indexes to the small root volume and the data
    # volume sits unused.
    DATA_DEV=""
    for candidate in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
      if [ -b "$candidate" ]; then
        DATA_DEV="$candidate"
        break
      fi
    done
    if [ -z "$DATA_DEV" ]; then
      echo "ERROR: Splunk data volume not found at /dev/nvme1n1, /dev/xvdf, or /dev/sdf." >&2
      exit 1
    fi
    if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
      mkfs.xfs -f "$DATA_DEV"
    fi
    mkdir -p /opt/splunk
    DATA_UUID=$(blkid -s UUID -o value "$DATA_DEV")
    if ! grep -q "$DATA_UUID" /etc/fstab; then
      echo "UUID=$DATA_UUID /opt/splunk xfs defaults,noatime 0 2" >> /etc/fstab
    fi
    mount /opt/splunk

    # Create splunk user
    useradd -r -m -s /bin/bash splunk

    # Download and install Splunk (URL pre-validated by check block)
    cd /opt
    SPLUNK_PKG="splunk-${var.splunk_version}-${var.splunk_build}-linux-amd64.tgz"
    wget -O "$${SPLUNK_PKG}" "${local.splunk_pkg_url}"
    wget -O "$${SPLUNK_PKG}.sha512" "${local.splunk_pkg_url}.sha512"
    sha512sum -c "$${SPLUNK_PKG}.sha512" || { echo "ERROR: Splunk package checksum mismatch. Aborting." >&2; exit 1; }
    tar -xzf "$${SPLUNK_PKG}"
    chown -R splunk:splunk /opt/splunk

    # Retrieve Splunk admin password from SSM Parameter Store (never stored in user_data)
    SPLUNK_PASSWORD=$(aws ssm get-parameter \
      --name "${var.splunk_password_ssm_name}" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text \
      --region ${data.aws_region.current.id})

    if [ -z "$SPLUNK_PASSWORD" ]; then
      echo "ERROR: Failed to retrieve Splunk password from SSM or password is empty. Aborting." >&2
      exit 1
    fi

    # Start Splunk and accept license
    sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$SPLUNK_PASSWORD"
    unset SPLUNK_PASSWORD

    # Enable Splunk to start at boot
    /opt/splunk/bin/splunk enable boot-start -user splunk

    # Configure basic settings
    sudo -u splunk /opt/splunk/bin/splunk set web-port 8000
    sudo -u splunk /opt/splunk/bin/splunk restart
    %{if var.enable_auto_lifecycle}

    # Auto-lifecycle: schedule shutdown ${var.auto_shutdown_minutes} minutes after every boot.
    # cloud-init per-boot scripts run on every instance start (first boot and subsequent restarts).
    mkdir -p /var/lib/cloud/scripts/per-boot
    cat > /var/lib/cloud/scripts/per-boot/auto-shutdown.sh << 'SHUTDOWN'
#!/bin/bash
# Guard: only shut down if Splunk is installed (skip first-boot provisioning run).
if [ -f /opt/splunk/bin/splunk ]; then
  /sbin/shutdown -h +${var.auto_shutdown_minutes}
fi
SHUTDOWN
    chmod +x /var/lib/cloud/scripts/per-boot/auto-shutdown.sh
    %{endif}
  EOF
  )
}

# Splunk Instance
resource "aws_instance" "splunk" {
  ami                         = var.ami_id
  instance_type               = var.splunk_instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = var.splunk_security_group_ids
  subnet_id                   = var.subnet_ids[0]
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.splunk_instance_profile_name

  user_data_base64 = local.splunk_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = var.splunk_root_volume_size
    encrypted   = true

    tags = merge(local.common_tags, {
      Name = "${var.environment}-splunk-root"
    })
  }

  # Additional EBS volume for Splunk data
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_type = "gp3"
    volume_size = var.splunk_data_volume_size
    encrypted   = true

    tags = merge(local.common_tags, {
      Name = "${var.environment}-splunk-data"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-instance"
    Role = "splunk"
  })

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = data.http.splunk_pkg.status_code == 200
      error_message = "Splunk package not found at ${local.splunk_pkg_url} (HTTP ${data.http.splunk_pkg.status_code}). Check splunk_version and splunk_build."
    }
  }
}

# CloudWatch Log Group for Splunk instance
resource "aws_cloudwatch_log_group" "splunk" {
  name              = "/aws/ec2/${var.environment}-splunk"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-logs"
  })
}

# CloudWatch Log Group for Splunk application logs
resource "aws_cloudwatch_log_group" "splunk_app" {
  name              = "/splunk/${var.environment}"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-app-logs"
  })
}

# Auto-lifecycle: EventBridge Scheduler starts Splunk on a recurring schedule.
# Per-boot script (in user_data above) shuts it down after auto_shutdown_minutes.
# All resources below are only created when enable_auto_lifecycle = true.

resource "aws_iam_role" "lifecycle_scheduler" {
  count = var.enable_auto_lifecycle ? 1 : 0

  name = "${var.environment}-splunk-lifecycle-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lifecycle_scheduler" {
  count = var.enable_auto_lifecycle ? 1 : 0

  name = "${var.environment}-splunk-lifecycle-scheduler"
  role = aws_iam_role.lifecycle_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StartInstances"]
      Resource = "arn:aws:ec2:*:*:instance/${aws_instance.splunk.id}"
    }]
  })
}

resource "aws_scheduler_schedule" "splunk_start" {
  count = var.enable_auto_lifecycle ? 1 : 0

  name        = "${var.environment}-splunk-start"
  description = "Start Splunk every ${var.lifecycle_interval_hours} hours for data indexing"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(${var.lifecycle_interval_hours} ${local.lifecycle_schedule_unit})"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.lifecycle_scheduler[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.splunk.id]
    })
  }
}
