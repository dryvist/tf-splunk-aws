# TF-Splunk-AWS

[![CI](https://github.com/JacobPEvans/tf-splunk-aws/actions/workflows/terraform.yml/badge.svg)](https://github.com/JacobPEvans/tf-splunk-aws/actions/workflows/terraform.yml)
[![License](https://img.shields.io/github/license/JacobPEvans/tf-splunk-aws)](LICENSE)

Cost-optimized Splunk infrastructure on AWS using OpenTofu and Terragrunt.
**~$8.54–$17.67/month** (optional auto-lifecycle). This module provisions a
Splunk-ready AWS footprint — network, security, compute, and a running Splunk
instance — that a downstream configurator can take over for index and data setup.

## What & Why

**What**: Production-ready Splunk deployment on AWS with modular Terraform architecture
**Why**: Demonstrates cost optimization, infrastructure-as-code best practices, and security-first design

## Quick Facts

- **Cost**: ~$17.67/month always-on; ~$8.54/month with `enable_auto_lifecycle = true`
- **Architecture**: 4 modules (network, security, compute, splunk)
- **Deployment**: Terragrunt-managed with remote state
- **Security**: Encrypted storage, IAM least privilege, VPC isolation

## Cost Breakdown

| Resource | Always-On | Auto-Lifecycle |
| -------- | --------- | -------------- |
| NAT Instance (t4g.nano) | $2.52 | $2.52 |
| Splunk Instance (t4g.small) | $12.18 | ~$3.05 (25% utilization) |
| EBS Storage (70GB GP3) | $2.97 | $2.97 |
| **Total** | **~$17.67** | **~$8.54** |

Index data lives on the local EBS volume. This module deliberately stops at the
storage boundary: long-term archive to S3 is left to an out-of-band pipeline and
is not managed here. Auto-lifecycle (`enable_auto_lifecycle = true`) starts
Splunk every 4 hours for 60 minutes.

## Installation

This repo pins its toolchain (`tofu`, `terragrunt`, and friends) in a
[Nix dev shell][nix-develop], wired up through the committed `.envrc`. Activate it
once per worktree — `direnv` reads `.envrc` and loads the shell automatically:

```bash
direnv allow
```

AWS credentials must be available in the environment (the remote state backend
and provider both authenticate against AWS).

[nix-develop]: https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop.html

## Usage

Each environment lives under `terragrunt/` (`dev`, `stg`, `prod`). Plan and apply
from the target environment directory:

```bash
cd terragrunt/dev
terragrunt plan    # Review 22 resources
terragrunt apply   # Deploy infrastructure
```

## Documentation

| Document | Purpose | Read Time |
| -------- | ------- | --------- |
| **[Project Scope](.copilot/PROJECT.md)** | Business context, constraints | 2 min |
| **[Architecture](.copilot/ARCHITECTURE.md)** | Technical decisions, current state | 5 min |
| **[Implementation](modules/README.md)** | Module details, developer guide | 10 min |

---

> Part of a [larger ecosystem of ~40 repos](https://docs.jacobpevans.com) — see how it all fits together.
