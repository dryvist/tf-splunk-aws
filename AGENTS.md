# tf-splunk-aws

AWS Splunk/Cribl data-ingest infrastructure managed with OpenTofu (no
Terraform, no Terragrunt).

## Purpose

This repo provisions a cost-optimized AWS environment for on-demand Splunk
and/or Cribl workloads. Key constraints:

- Data flows **INTO** AWS only (never out — egress costs)
- Nothing needs 24/7 uptime; the environment is summoned on demand and a
  scheduled stop turns it off again (default nightly, caps runtime under 24h)
- Cost sensitivity is paramount
- Splunk and Cribl are independently optional (`enable_splunk`,
  `enable_cribl`)

## Architecture

```text
ROOT MODULE (repo root)
  modules/network    -> VPC, subnets, route tables
  modules/security   -> Security groups, IAM roles/profiles, SSM password
  modules/compute    -> NAT instance (t4g.nano, public subnet)
  modules/splunk     -> Splunk Enterprise (t3a.small x86, optional)
  modules/cribl      -> Cribl Stream (Linux) + Cribl Edge (Windows) (optional)
  modules/cribl-config -> Declarative Cribl objects (criblio provider, optional)
  modules/lifecycle  -> Scheduled stop of Project-tagged instances via the
                        AWS-StopEC2Instance runbook (EventBridge Scheduler)
  modules/summon     -> GitHub Actions OIDC role for credential-less
                        start/stop

NETWORK
  VPC: 10.0.0.0/16
  Public:  10.0.1.0/24, 10.0.2.0/24 (NAT lives here)
  Private: 10.0.10.0/24, 10.0.20.0/24 (workloads by default)
```

## Technology stack

- **OpenTofu** >= 1.10 (`tofu` CLI only — never generate `terraform` or
  `terragrunt` commands)
- **AWS provider** ~> 6.0
- **S3 remote state** with native lockfile locking (no DynamoDB)
- **SSM Parameter Store** for instance secrets

## Commands

Offline validation and tests need no credentials:

```bash
tofu fmt -check -recursive
tofu init -backend=false
tofu validate
tofu test -no-color
```

Real plans/applies use the standard AWS credential chain plus a var file:

```bash
tofu init -backend-config=envs/dev.s3.tfbackend   # once per environment
tofu plan  -var-file=envs/dev.tfvars
tofu apply -var-file=envs/dev.tfvars
```

Secrets and operator IPs come from the environment, never from committed
files: `TF_VAR_splunk_admin_password` (optional; generated when unset) and
`TF_VAR_admin_ip_cidrs` (e.g. `'["203.0.113.7/32"]'`).

### Post-apply: show cost and credentials

After every `tofu apply`, run and display:

```bash
tofu output -json estimated_cost | jq .
tofu output -json access_credentials | jq .
```

Then verify enabled service URLs respond before reporting success (services
take 2–5 minutes to boot; retry up to 3 times at 30-second intervals):

```bash
curl -sf -o /dev/null -w '%{http_code}' http://<splunk_ip>:8000   # expect 303
curl -sf -o /dev/null -w '%{http_code}' http://<cribl_ip>:4200    # expect 200/302
```

## Secrets management

**NEVER** commit passwords or credentials. Use:

- `aws_ssm_parameter` (SecureString) for the Splunk admin password —
  retrieved at boot via the instance role
- `TF_VAR_*` environment variables for operator-supplied secrets
- Mark secret variables `sensitive = true`

## Testing

Tests use mock providers — no AWS credentials needed. Run the whole suite with
`tofu test`. Test files live in `tests/` (one `*.tftest.hcl` per concern).

## Version management

Pin dependency versions for reproducibility: `~> X.Y` for providers (patch
flexibility, locked major/minor), `>= X.Y` only for true minimums like
`required_version`.

## Development workflow

Before ANY commit: `tofu fmt -check -recursive`, `tofu init -backend=false`,
`tofu validate`, `tofu test -no-color`. Use feature branches and
[Conventional Commits](https://www.conventionalcommits.org); releases are cut
by release-please.

## PR review checklist

- [ ] No exposed secrets or credentials
- [ ] Variables documented, `sensitive = true` where needed
- [ ] `tofu validate` and `tofu test` pass (no credentials needed)
- [ ] Conventional commit message
- [ ] Documentation updated if needed
- [ ] Cost impact considered
