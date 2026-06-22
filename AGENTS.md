# tf-splunk-aws

AWS Splunk DR/backup infrastructure managed with Terraform and Terragrunt.

## Purpose

This repo provisions a cost-optimized AWS environment for backup/DR of a local home-lab Splunk instance. Key constraints:

- Data flows **INTO** AWS only (never out - egress costs)
- Only a minimal data receiver needs 24/7 uptime
- Search capability is on-demand (start/stop as needed)
- Cost sensitivity is paramount

## Architecture

```text
MODULES
  network  -> VPC, subnets, route tables (us-east-2)
  security -> Security groups, IAM role/profile
  compute  -> NAT instance (t4g.nano, public subnet)
  splunk   -> Splunk Enterprise (t4g.small, private subnet)

DATA FLOW
  On-Prem Splunk -> HEC (port 8088) -> AWS Splunk Receiver (private subnet via NAT)
  Cloud Sources  -> HEC (port 8088) -> AWS Splunk Receiver

LONG-TERM ARCHIVE
  Cribl writes directly to S3 outside this module — Splunk indexes stay local on EBS.

NETWORK
  VPC: 10.0.0.0/16
  Public:  10.0.1.0/24, 10.0.2.0/24 (NAT instance lives here)
  Private: 10.0.10.0/24, 10.0.20.0/24 (Splunk lives here)
```

## Cost

| Resource | Always-On | Auto-Lifecycle |
| -------- | --------- | -------------- |
| NAT (t4g.nano) | ~$2.52/mo | ~$2.52/mo |
| Splunk (t4g.small) | ~$12.18/mo | ~$3.05/mo (25% utilization) |
| EBS (70GB gp3) | ~$2.97/mo | ~$2.97/mo |
| **Total** | **~$17.67/mo** | **~$8.54/mo** |

Auto-lifecycle (`enable_auto_lifecycle = true`) starts Splunk every 4 hours for 60 minutes via EventBridge Scheduler.
Index data lives on the EBS data volume; long-term archive is handled by Cribl writing directly to S3 outside this module.

## Technology Stack

- **Terraform/OpenTofu** >= 1.0
- **AWS Provider** ~> 6.0
- **Terragrunt** for environment management
- **SSM Parameter Store** for secrets (Splunk admin password stored as SecureString)

## Dev Shell Activation

This repo uses the shared [nix-devenv terraform shell](https://github.com/JacobPEvans/nix-devenv/tree/main/shells/terraform)
via direnv for reproducible tooling:

```bash
# Automatic (recommended): direnv activates on cd
cd ~/git/tf-splunk-aws/main/
direnv allow    # one-time per worktree

# Manual:
nix develop "github:JacobPEvans/nix-devenv?dir=shells/terraform"
```

## Claude Code with AWS Credentials

Claude Code cannot access the macOS keychain for `aws-vault` prompts. To run
Terragrunt operations (init, plan, apply, destroy) from Claude, **start the
session with credentials already injected**:

```bash
# Launch Claude Code with AWS credentials pre-loaded
aws-vault exec tf-splunk-aws -- doppler run -- claude

# All Bash tool calls inside the session inherit AWS_* and Doppler env vars.
# No aws-vault or doppler wrapper needed on individual commands:
#   terragrunt init
#   terragrunt plan
#   terragrunt apply
#   terragrunt destroy -auto-approve
```

STS credentials last ~1 hour. If they expire mid-session, exit and re-launch.

### Post-Apply: Always Show Cost and Credentials

After **every** `terragrunt apply` (or any change to this module), always run and
display these outputs to the user:

```bash
cd terragrunt/dev/
terragrunt output -json estimated_cost | jq .
terragrunt output -json access_credentials | jq .
```

Then **verify all service URLs are live** before reporting success:

```bash
# Check Splunk Web (expect HTTP 303 redirect to login)
curl -sf -o /dev/null -w '%{http_code}' http://<splunk_ip>:8000 || echo "SPLUNK DOWN"

# Check Cribl Stream Web UI (expect HTTP 200 or 302)
curl -sf -o /dev/null -w '%{http_code}' http://<cribl_stream_ip>:4200 || echo "CRIBL STREAM DOWN"
```

Services may take 2-5 minutes to boot after apply. Retry up to 3 times with 30-second
intervals before reporting a service as down. Report results alongside the cost/credentials output.

Offline operations (validate, test) never need credentials — run them directly:

```bash
cd modules/
tofu init -backend=false
tofu validate
tofu test -no-color
```

## Commands

### Prerequisites

- `aws-vault` for AWS credential management
- `doppler` for environment variable injection (if using Doppler secrets)

### Remote State Bootstrap (first-time / new AWS account)

The S3 bucket and DynamoDB table for Terragrunt remote state must exist before running
`terragrunt init`. They are created manually once per account:

```bash
# Create S3 bucket (deterministic name — no random suffix)
aws-vault exec tf-splunk-aws -- aws s3api create-bucket \
  --bucket tf-splunk-aws-state-useast2-$(aws-vault exec tf-splunk-aws -- aws sts get-caller-identity --query Account --output text) \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

# Enable versioning and encryption
aws-vault exec tf-splunk-aws -- aws s3api put-bucket-versioning \
  --bucket tf-splunk-aws-state-useast2-<ACCOUNT_ID> \
  --versioning-configuration Status=Enabled

aws-vault exec tf-splunk-aws -- aws s3api put-bucket-encryption \
  --bucket tf-splunk-aws-state-useast2-<ACCOUNT_ID> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws-vault exec tf-splunk-aws -- aws dynamodb create-table \
  --table-name tf-splunk-aws-locks-useast2 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-2
```

Once these resources exist, `terragrunt init` will succeed and manage the state backend automatically.

### Terraform Operations

```bash
# From terragrunt/dev/ (uses assume-role via tf-splunk-aws profile)
aws-vault exec tf-splunk-aws -- doppler run -- terragrunt init
aws-vault exec tf-splunk-aws -- doppler run -- terragrunt plan
aws-vault exec tf-splunk-aws -- doppler run -- terragrunt apply

# From modules/ (for testing without real credentials)
tofu init -backend=false
tofu validate
tofu test -no-color
```

### Doppler Environment Variables

| Variable | Source | Purpose |
| -------- | ------ | ------- |
| `SPLUNK_PASSWORD` | Doppler | Splunk admin password (>= 8 chars) |
| `NETWORK_PUBLIC_IP_ADDRESS` | Doppler | Home IP for web/HEC CIDR allowlists |

## Module Structure

```text
modules/
├── main.tf         # Root orchestrator, wires modules together
├── variables.tf    # Root input variables
├── outputs.tf      # Aggregated outputs
├── network/        # VPC, subnets, route tables, IGW
├── security/       # Security groups, IAM role/profile
├── compute/        # NAT instance (source_dest_check=false)
└── splunk/         # Splunk Enterprise instance + EBS
```

## Secrets Management

**NEVER** commit passwords or credentials. Use:

- `aws_ssm_parameter` (SecureString) for Splunk admin password — retrieved at boot via `aws ssm get-parameter`
- `aws-vault` for AWS credentials
- Instance role + SSM for instance-level secrets

## Testing

Tests use mock providers - no AWS credentials needed:

```bash
cd modules/
tofu init -backend=false
tofu test -no-color
```

## Security Notes

- SSH disabled by default (`ssh_allowed_cidrs = []` — empty list creates no SSH rule)
- SSH access requires explicit CIDR allowlist via `ssh_allowed_cidrs` variable
- Use SSM Session Manager for shell access (already installed on all instances)
- All instances in private subnets except NAT
- Splunk accessible only from within VPC

## Critical: Version Management

Pin dependency versions for reproducibility. Use `~> X.Y` for patch-level flexibility
while locking major/minor versions. This avoids unexpected breaking changes from upstream
updates while still receiving bug fixes.

- Use `~> X.Y` (e.g., `~> 6.0`) for provider versions — allows patch releases, locks major/minor
- Use `>= X.Y` only when a minimum version is required and newer versions are all acceptable
- Avoid overly tight constraints (e.g., `= X.Y.Z`) unless exact reproducibility is critical

## Development Workflow

**Before ANY commits**, run validation:

```bash
# Validate syntax (no credentials needed)
tofu init -backend=false
tofu validate

# Full plan (requires AWS credentials)
aws-vault exec tf-splunk-aws -- doppler run -- terragrunt plan
```

**Best Practices**:

- Use feature branches for all changes
- Follow conventional commit messages
- Mark secrets with `sensitive = true` in variables
- Never commit `.terraform/` or state files
- Remote state with encryption (S3 + DynamoDB)

## PR Review Checklist

- [ ] No exposed secrets or credentials
- [ ] Variables documented with `sensitive = true` where needed
- [ ] `tofu validate` passes (no credentials needed)
- [ ] Conventional commit message
- [ ] Documentation updated if needed
- [ ] Cost impact considered
