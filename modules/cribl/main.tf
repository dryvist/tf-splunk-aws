# Cribl module — Cribl Stream (Linux leader) and Cribl Edge (Windows worker).
# Edge connects to Stream's private IP on the Cribl web/leader port. All
# resources are gated on var.enable_cribl.

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

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_tag
    ManagedBy   = "opentofu"
  }

  # Guard against null when enable_cribl = false — locals are evaluated even
  # when every resource in the module has count = 0.
  windows_admin_password = coalesce(var.windows_admin_password, "unused")

  # Download URLs — validated at plan/apply time via data "http" resources
  cribl_stream_rpm_url = "${var.cribl_download_base_url}/dl/${var.cribl_version}/cribl-${var.cribl_version}-${var.cribl_build}-linux-x64.rpm"
  cribl_edge_zip_url   = "${var.cribl_download_base_url}/dl/${var.cribl_version}/cribl-${var.cribl_version}-${var.cribl_build}-windows-x64.zip"
}

# Pre-deployment validation: verify download URLs exist before creating instances
data "http" "cribl_stream_rpm" {
  count  = var.enable_cribl ? 1 : 0
  url    = local.cribl_stream_rpm_url
  method = "HEAD"
}

data "http" "cribl_edge_zip" {
  count  = var.enable_cribl ? 1 : 0
  url    = local.cribl_edge_zip_url
  method = "HEAD"
}

# Cribl Stream user_data — install via RPM, configure as leader
locals {
  cribl_stream_user_data = base64encode(<<-EOF
    #!/bin/bash
    set -eo pipefail
    yum update -y

    # Install SSM agent (should be pre-installed on Amazon Linux 2)
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Create cribl user
    useradd -r -m -s /bin/bash cribl

    # Download and install Cribl Stream via RPM (URL pre-validated by data "http")
    cd /tmp
    CRIBL_RPM="cribl-${var.cribl_version}-${var.cribl_build}-linux-x64.rpm"
    curl -fsSL -o "$CRIBL_RPM" "${local.cribl_stream_rpm_url}"
    curl -fsSL -o "$CRIBL_RPM.sha256" "${local.cribl_stream_rpm_url}.sha256"
    sha256sum -c "$CRIBL_RPM.sha256" || { echo "ERROR: Cribl Stream RPM checksum mismatch. Aborting." >&2; exit 1; }
    rpm -ivh "$CRIBL_RPM"
    chown -R cribl:cribl /opt/cribl

    # Configure as leader mode via config before first start
    mkdir -p /opt/cribl/local/cribl
    cat > /opt/cribl/local/cribl/cribl.yml << 'CRIBL_CFG'
distributed:
  mode: master
  group: default
api:
  host: 0.0.0.0
  port: ${var.cribl_web_port}
CRIBL_CFG
    chown -R cribl:cribl /opt/cribl/local

    # Enable boot-start via systemd and start (--no-block avoids systemd timeout on slow instances)
    /opt/cribl/bin/cribl boot-start enable -m systemd -u cribl
    systemctl start cribl --no-block
  EOF
  )
}

# Cribl Edge user_data — Windows PowerShell, ZIP install connecting to Stream leader
locals {
  cribl_edge_user_data = base64encode(<<-WINEOF
<powershell>
# Set Administrator password (auto-generated per-build)
$ErrorActionPreference = "Stop"
$adminPassword = ConvertTo-SecureString "${local.windows_admin_password}" -AsPlainText -Force
Get-LocalUser -Name "Administrator" | Set-LocalUser -Password $adminPassword

# Install Cribl Edge and connect to Stream leader
$criblVersion = "${var.cribl_version}"
$criblBuild = "${var.cribl_build}"
$streamIp = "${try(aws_instance.cribl_stream[0].private_ip, "")}"
$zipUrl = "${local.cribl_edge_zip_url}"
$zipPath = "C:\Windows\Temp\cribl-edge.zip"
$installDir = "C:\Program Files\Cribl"

# Download and verify checksum
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
$sha256File = $zipPath + ".sha256"
Invoke-WebRequest -Uri ($zipUrl + ".sha256") -OutFile $sha256File
$expectedHash = (Get-Content $sha256File -Raw).Split(" ")[0].Trim().ToUpper()
$actualHash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToUpper()
if ($actualHash -ne $expectedHash) {
  throw "ERROR: Cribl Edge ZIP checksum mismatch. Expected: $expectedHash Actual: $actualHash"
}
Expand-Archive -Path $zipPath -DestinationPath $installDir -Force

# Configure as managed edge connecting to Stream leader
& "$installDir\cribl\bin\cribl.cmd" mode-managed-edge
Set-Content -Path "$installDir\cribl\local\cribl.yml" -Value @"
distributed:
  mode: managed-edge
  master:
    host: $streamIp
    port: ${var.cribl_web_port}
"@

# Install and start as Windows service
& "$installDir\cribl\bin\cribl.cmd" boot-start enable
Start-Service Cribl
</powershell>
  WINEOF
  )
}

# Cribl Stream Instance (Linux)
resource "aws_instance" "cribl_stream" {
  count = var.enable_cribl ? 1 : 0

  ami                         = var.linux_ami_id
  instance_type               = var.cribl_stream_instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = var.security_group_ids
  subnet_id                   = var.subnet_ids[0]
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.instance_profile_name

  user_data_base64 = local.cribl_stream_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true

    tags = merge(local.common_tags, {
      Name = "${var.environment}-cribl-stream-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-stream"
    Role = "cribl-stream"
  })

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = data.http.cribl_stream_rpm[0].status_code == 200
      error_message = "Cribl Stream RPM not found at ${local.cribl_stream_rpm_url} (HTTP ${try(data.http.cribl_stream_rpm[0].status_code, "unknown")}). Check cribl_version and cribl_build."
    }
  }
}

# Cribl Edge Instance (Windows Server 2022)
resource "aws_instance" "cribl_edge" {
  count = var.enable_cribl ? 1 : 0

  ami                         = var.windows_ami_id
  instance_type               = var.cribl_edge_instance_type
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = var.security_group_ids
  subnet_id                   = var.subnet_ids[0]
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.instance_profile_name

  user_data_base64 = local.cribl_edge_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true

    tags = merge(local.common_tags, {
      Name = "${var.environment}-cribl-edge-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-edge"
    Role = "cribl-edge"
  })

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = data.http.cribl_edge_zip[0].status_code == 200
      error_message = "Cribl Edge ZIP not found at ${local.cribl_edge_zip_url} (HTTP ${try(data.http.cribl_edge_zip[0].status_code, "unknown")}). Check cribl_version and cribl_build."
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "cribl_stream" {
  count = var.enable_cribl ? 1 : 0

  name              = "/aws/ec2/${var.environment}-cribl-stream"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-stream-logs"
  })
}

resource "aws_cloudwatch_log_group" "cribl_edge" {
  count = var.enable_cribl ? 1 : 0

  name              = "/aws/ec2/${var.environment}-cribl-edge"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${var.environment}-cribl-edge-logs"
  })
}
