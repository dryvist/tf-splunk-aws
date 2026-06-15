# TF-Splunk-AWS

[![CI](https://github.com/JacobPEvans/tf-splunk-aws/actions/workflows/terraform.yml/badge.svg)](https://github.com/JacobPEvans/tf-splunk-aws/actions/workflows/terraform.yml)
[![License](https://img.shields.io/github/license/JacobPEvans/tf-splunk-aws)](LICENSE)

Cost-optimized Splunk infrastructure on AWS using OpenTofu and Terragrunt.
**~$8.54–$17.67/month** (optional auto-lifecycle). Long-term archive is handled
by Cribl writing directly to S3 outside this module.

## What & Why

**What**: Production-ready Splunk deployment on AWS with modular Terraform architecture
**Why**: Demonstrates cost optimization, infrastructure-as-code best practices, and security-first design

## Quick Facts

- **Cost**: ~$17.67/month while running; an `enable_auto_stop` guardrail stops the whole stack 48h after each start so it can't quietly run up the bill
- **Architecture**: 4 modules (network, security, compute, splunk)
- **Deployment**: Terragrunt-managed with remote state
- **Security**: Encrypted storage, IAM least privilege, VPC isolation

## Cost Breakdown

| Resource | Running | Stopped (by guardrail) |
| -------- | ------- | ---------------------- |
| NAT Instance (t4g.nano) | $2.52 | $0 |
| Splunk Instance (t3a.small) | $12.18 | $0 |
| EBS Storage (70GB GP3) | $2.97 | $2.97 |
| **Total** | **~$17.67** | **~$2.97** |

Index data lives on the local EBS volume. Cribl handles long-term archive to S3
out-of-band, so this module no longer manages a SmartStore bucket.
The `enable_auto_stop` guardrail (an hourly Lambda) stops every `Project=splunk-aws`
instance 48h after it starts, so the stack only costs the "Running" rate while
actively in use and drops to EBS-only once stopped — compute and public-IPv4
charges stop with the instances.

## Quick Start

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
