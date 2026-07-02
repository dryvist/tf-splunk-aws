# Instance Management — Summon, Pause & Resume

Procedures for starting and stopping the environment to save money without
destroying any infrastructure or data. Stopped instances cost only their EBS
storage; all index data survives on the persistent data volume.

## Primary path: the summon workflow (no AWS credentials)

With `enable_github_summon = true` applied and the repository variables wired
(see the README's "First-time AWS setup"), anyone with write access to the
repository can start or stop the stack:

1. GitHub → **Actions → Summon environment → Run workflow**
2. Choose `action: start` (with an optional `lease_hours`, default 24) or
   `action: stop`
3. The job summary shows every instance's state and IPs when it finishes

Equivalent CLI and chat triggers:

```bash
gh workflow run summon.yml -f action=start -f lease_hours=24
gh workflow run summon.yml -f action=stop
```

Slack users with the [GitHub app for Slack](https://github.com/integrations/slack)
can trigger the same workflow with `/github run <owner>/<repo> summon.yml`.

On `start`, the workflow:

- starts the NAT instance first (private-subnet instances need their egress
  path up before they boot), then the workload instances;
- creates a **one-time, self-deleting stop lease** that stops the whole stack
  after `lease_hours`.

## Automatic shutdown guarantees

Independent of how instances were started, the lifecycle module (default
`enable_auto_stop = true`) runs an hourly sweep that stops any
`Project`-tagged instance whose uptime exceeds `max_runtime_hours`
(default 24). Console or CLI starts are covered too — there is no way to
leave the stack running indefinitely by accident.

There is no auto-*start*: the stack stays off until deliberately summoned.

## Fallback: manual AWS CLI

Requires credentials with `ec2:StartInstances` / `ec2:StopInstances` on the
tagged instances.

```bash
# Discover instance IDs by tag
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=splunk-aws" \
  --query 'Reservations[].Instances[].{id:InstanceId,name:Tags[?Key==`Name`]|[0].Value,state:State.Name}' \
  --output table

# Stop (workloads first, NAT last — order is a nicety, not a requirement)
aws ec2 stop-instances --instance-ids <workload-ids> <nat-id>

# Start (NAT first so private instances have egress when they boot)
aws ec2 start-instances --instance-ids <nat-id>
aws ec2 wait instance-running --instance-ids <nat-id>
aws ec2 start-instances --instance-ids <workload-ids>
```

## After a restart

- Public IPs change on every stop/start cycle (no Elastic IPs are allocated,
  by design — an EIP attached to a stopped instance bills hourly). Fetch the
  new IPs from the summon job summary or `describe-instances`.
- Splunk and Cribl are installed as boot-start services; first-boot
  provisioning does not repeat. Give services 2–5 minutes after start.
- If access stops working after a restart, your operator IP may have changed:
  update `TF_VAR_admin_ip_cidrs` and re-apply.
