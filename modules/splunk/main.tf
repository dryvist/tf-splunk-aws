# Splunk module — the Splunk Enterprise instance, its EBS data volume, and
# CloudWatch log groups. All resources are gated on var.enable_splunk.

terraform {
  required_version = ">= 1.6"
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

# Current AWS region (used in user_data for SSM parameter retrieval).
data "aws_region" "current" {}

locals {
  enabled = var.enable_splunk ? 1 : 0

  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }

  # Guard against null when enable_splunk = false — locals are evaluated even
  # when every resource in the module has count = 0.
  splunk_password_ssm_name = coalesce(var.splunk_password_ssm_name, "unused")

  splunk_pkg_url = "${var.splunk_download_base_url}/products/splunk/releases/${var.splunk_version}/linux/splunk-${var.splunk_version}-${var.splunk_build}-linux-amd64.tgz"
}

# Fail at plan time (not mid-boot) if the requested version/build does not
# exist at the download URL.
data "http" "splunk_pkg" {
  count = local.enabled

  url    = local.splunk_pkg_url
  method = "HEAD"
}

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

    # Download and install Splunk (URL pre-validated at plan time)
    cd /opt
    SPLUNK_PKG="splunk-${var.splunk_version}-${var.splunk_build}-linux-amd64.tgz"
    wget -O "$${SPLUNK_PKG}" "${local.splunk_pkg_url}"
    wget -O "$${SPLUNK_PKG}.sha512" "${local.splunk_pkg_url}.sha512"
    sha512sum -c "$${SPLUNK_PKG}.sha512" || { echo "ERROR: Splunk package checksum mismatch. Aborting." >&2; exit 1; }
    tar -xzf "$${SPLUNK_PKG}"
    chown -R splunk:splunk /opt/splunk

    # Retrieve Splunk admin password from SSM Parameter Store (never stored in user_data)
    SPLUNK_PASSWORD=$(aws ssm get-parameter \
      --name "${local.splunk_password_ssm_name}" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text \
      --region ${data.aws_region.current.region})

    if [ -z "$SPLUNK_PASSWORD" ]; then
      echo "ERROR: Failed to retrieve Splunk password from SSM or password is empty. Aborting." >&2
      exit 1
    fi

    # Start Splunk and accept license
    sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$SPLUNK_PASSWORD"
    unset SPLUNK_PASSWORD

    # Enable Splunk to start at boot
    /opt/splunk/bin/splunk enable boot-start -user splunk

    # Splunk Web listens on its default port (8000) and the daemon is already
    # running from the `splunk start --seed-passwd` call above. `set web-port`
    # and `restart` are avoided here because they require an authenticated CLI
    # session, which the seed-passwd flow does not establish.
  EOF
  )
}

resource "aws_instance" "splunk" {
  count = local.enabled

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

  # Dedicated data volume — Splunk indexes live here (mounted at /opt/splunk
  # by user_data), so index data survives independent of the root volume.
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
      condition     = data.http.splunk_pkg[0].status_code == 200
      error_message = "Splunk package not found at ${local.splunk_pkg_url} (HTTP ${try(data.http.splunk_pkg[0].status_code, 0)}). Check splunk_version and splunk_build."
    }
  }
}

resource "aws_cloudwatch_log_group" "splunk" {
  count = local.enabled

  name              = "/aws/ec2/${var.environment}-splunk"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-logs"
  })
}

resource "aws_cloudwatch_log_group" "splunk_app" {
  count = local.enabled

  name              = "/splunk/${var.environment}"
  retention_in_days = 90

  tags = merge(local.common_tags, {
    Name = "${var.environment}-splunk-app-logs"
  })
}
