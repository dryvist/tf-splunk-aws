# tf-splunk-aws

[![OpenTofu CI](../../actions/workflows/tofu-ci.yml/badge.svg)](../../actions/workflows/tofu-ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Cost-optimized Splunk Enterprise and/or Cribl environment on AWS, managed with
plain [OpenTofu](https://opentofu.org). Instances stop themselves after 24
hours, and authorized GitHub users can start ("summon") the environment from
the Actions tab with zero AWS credentials.

## What & Why

This repository provisions an on-demand data-ingest environment:

- **Splunk Enterprise** (optional, on by default) — a single indexer/search
  head with a dedicated EBS data volume.
- **Cribl Stream + Cribl Edge** (optional, off by default) — a Linux Stream
  leader and a Windows Edge worker for routing/shaping data.
- **Shared plumbing** — VPC with public/private subnets, a t4g.nano NAT
  instance (instead of a ~$32/mo NAT Gateway), security groups, IAM, and
  SSM-based secrets.

Either workload deploys independently (`enable_splunk` / `enable_cribl`);
cost control is built in rather than bolted on.

## Cost

Approximate on-demand pricing in us-east-2 (see the `estimated_cost` output
for the live computed figure):

| Component | Running | Stopped |
| --------- | ------- | ------- |
| NAT instance (t4g.nano) | ~$3.07/mo | $0 |
| Splunk (t3a.small + 70 GB gp3) | ~$19.32/mo | ~$5.60/mo (EBS) |
| Cribl Stream (t3a.small) | ~$16.12/mo | ~$2.40/mo (EBS) |
| Cribl Edge (t3a.medium, Windows) | ~$56.71/mo | ~$2.40/mo (EBS) |
| Auto-stop schedule | ~$0 (free tier) | ~$0 |

With the default guardrail, a daily stop caps runtime at under 24 hours, so
real spend approaches the "stopped" column plus hours actually used.

### Automatic shutdown (default on)

`modules/lifecycle` provisions an EventBridge Scheduler that invokes AWS's
built-in `AWS-StopEC2Instance` SSM runbook on `stop_schedule_expression`
(default `cron(0 8 * * ? *)` — nightly 08:00 UTC), stopping every instance
tagged `Project=splunk-aws`. It is tag-driven and fully AWS-native (no code),
so it catches every instance regardless of how it was started. A daily
schedule caps maximum runtime at under 24 hours.

## Installation

Requirements:

- [OpenTofu](https://opentofu.org) >= 1.10 (`tofu`)
- AWS CLI v2 with credentials for the target account (env vars, SSO, or any
  standard credential source)

```bash
git clone <this-repo>
cd tf-splunk-aws
```

## First-time AWS setup

One-time, per AWS account. Run with an admin-capable identity.

### 1. Create the state bucket

State locking uses S3 native lockfiles (OpenTofu >= 1.10) — no DynamoDB table.
This is a greenfield backend (bucket/key/locking all changed from the old
Terragrunt setup: `useast2`→`us-east-2`, dropped the `terragrunt/` key prefix,
DynamoDB→S3 lockfile) — nothing carries over from a prior Terragrunt state.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-2
BUCKET="tf-splunk-aws-state-${REGION}-${ACCOUNT_ID}"

aws s3api create-bucket \
  --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Then replace `<ACCOUNT_ID>` in `envs/*.s3.tfbackend` with your account id.

### 2. Create the deployer policy and role/user

The identity that runs `tofu plan/apply` needs the policy below (replace
`<ACCOUNT_ID>`). Attach it to a role (recommended, e.g. via your SSO
permission set) or an IAM user.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::tf-splunk-aws-state-us-east-2-<ACCOUNT_ID>",
        "arn:aws:s3:::tf-splunk-aws-state-us-east-2-<ACCOUNT_ID>/*"
      ]
    },
    {
      "Sid": "NetworkAndCompute",
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    },
    {
      "Sid": "InstanceSecrets",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:ListTagsForResource",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "ssm:DescribeParameters"
      ],
      "Resource": "arn:aws:ssm:*:<ACCOUNT_ID>:parameter/*/splunk/*"
    },
    {
      "Sid": "GuardrailScheduling",
      "Effect": "Allow",
      "Action": "scheduler:*",
      "Resource": "arn:aws:scheduler:*:<ACCOUNT_ID>:schedule/default/*"
    },
    {
      "Sid": "Logs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:PutRetentionPolicy",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:ListTagsForResource",
        "logs:TagResource",
        "logs:UntagResource",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForInstanceAndSchedulerRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:PassRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::<ACCOUNT_ID>:role/*-splunk-*",
        "arn:aws:iam::<ACCOUNT_ID>:role/*-cribl-*",
        "arn:aws:iam::<ACCOUNT_ID>:role/*-splunk-aws-*",
        "arn:aws:iam::<ACCOUNT_ID>:instance-profile/*"
      ]
    },
    {
      "Sid": "GithubOidcProvider",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider"
      ],
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    {
      "Sid": "ReadOnlyLookups",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
```

> `ec2:*` on `*` is used because this stack creates and destroys VPCs,
> subnets, security groups, key pairs, volumes, and instances. Scope it
> further with tag conditions if your organization requires it.

### 3. Set secrets and variables

| Where | Name | Value |
| ----- | ---- | ----- |
| Shell env (optional) | `TF_VAR_splunk_admin_password` | Splunk admin password (>= 8 chars). Omit to auto-generate. |
| Shell env | `TF_VAR_admin_ip_cidrs` | Your operator egress IPs, e.g. `'["203.0.113.7/32"]'` |
| GitHub repo → Actions variables | `SUMMON_ROLE_ARN` | `tofu output -raw summon_role_arn` |
| GitHub repo → Actions variables | `AWS_REGION` (optional) | Defaults to `us-east-2` |

## Usage

```bash
# One-time per environment (after replacing <ACCOUNT_ID> in the tfbackend file)
tofu init -backend-config=envs/dev.s3.tfbackend

tofu plan  -var-file=envs/dev.tfvars
tofu apply -var-file=envs/dev.tfvars

# Connection details and generated credentials
tofu output connection_info
tofu output access_credentials
tofu output estimated_cost

# Tear down
tofu destroy -var-file=envs/dev.tfvars
```

Deploy only one workload by flipping the toggles in the tfvars file (or on
the CLI):

```bash
tofu apply -var-file=envs/dev.tfvars -var enable_splunk=false -var enable_cribl=true
```

### Summon: start/stop with zero AWS credentials

Set `enable_github_summon = true` and `github_repository = "<owner>/<repo>"`
in your tfvars, apply, and wire the `summon_role_arn` output into the
repository's `SUMMON_ROLE_ARN` Actions variable (table above). Then anyone with
write access to the repo can run **Actions → Summon environment → Run workflow**:

- `action: start` — starts the NAT instance first, then the workload
  instances, and prints instance IPs to the job summary. The scheduled stop
  (below) turns everything off again on its schedule.
- `action: stop` — stops every instance in the stack immediately.

Because it's a plain `workflow_dispatch`, it also works from anywhere that
can trigger GitHub workflows — the GitHub mobile app, `gh workflow run
summon.yml -f action=start`, or Slack via the
[GitHub app for Slack](https://github.com/integrations/slack)
(`/github run <owner>/<repo> summon.yml`).

## Module structure

```text
main.tf / variables.tf / outputs.tf   Root module (this directory)
envs/                                 Per-environment tfvars + backend configs
tests/                                Mock-provider test suite (tofu test)
modules/
├── network/      VPC, subnets, route tables, IGW
├── security/     Security groups, IAM roles/profiles, SSM password
├── compute/      NAT instance
├── splunk/       Splunk Enterprise instance + EBS data volume (optional)
├── cribl/        Cribl Stream (Linux) + Cribl Edge (Windows) (optional)
├── cribl-config/ Declarative Cribl objects via the criblio provider (optional)
├── lifecycle/    Scheduled stop via the AWS-StopEC2Instance runbook
└── summon/       GitHub Actions OIDC role for credential-less start/stop
```

## Testing

No AWS credentials needed — the suite uses mock providers:

```bash
tofu init -backend=false
tofu test -no-color
```

See [docs/instance-management.md](docs/instance-management.md) for day-2
start/stop operations.

## Security notes

- SSH is disabled by default (`ssh_allowed_cidrs = []` creates no SSH rule);
  use SSM Session Manager for shell access.
- The Splunk admin password lives in SSM Parameter Store (SecureString) and
  is fetched by the instance at boot — never embedded in user data.
- Workload instances sit in private subnets unless `splunk_public_access`
  is enabled, and even then every ingress port is allowlist-gated.
- `allow_all_ips` exists for short-lived testing only and is never committed.

## Contributing

1. Branch, change, and run the validation stack before pushing:
   `tofu fmt -check -recursive && tofu init -backend=false && tofu validate && tofu test -no-color`.
2. Use [Conventional Commits](https://www.conventionalcommits.org) — releases
   are cut automatically by release-please.
3. CI must be green (`OpenTofu CI`, `Markdown Lint`) before merge.

## License

[MIT](LICENSE)
