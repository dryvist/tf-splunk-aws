# Cribl Config Migration — Phase 1 Discovery

Status: Phase 1 (discovery, docs only). No code changes in this PR.

## Goal

Layer the official Cribl Terraform provider (`criblio/criblio`) on top of the
existing `modules/cribl/` infrastructure module. Manage Cribl Stream
configuration (worker groups, packs, pipelines, routes, sources, destinations,
collectors, knowledge objects) as code instead of via `user_data` shell.

Drop Windows entirely. Cribl Edge on Linux only going forward.

Build additively behind a feature flag, default off, until validated end-to-end.

## What exists today

`modules/cribl/` is a two-resource module that brings up:

| Resource | Type | Purpose |
| --- | --- | --- |
| `aws_instance.cribl_stream` | Amazon Linux 2 (x86_64), `t3a.small` | Stream leader, RPM install via `user_data` |
| `aws_instance.cribl_edge` | Windows Server 2022 (x86_64), `t3a.medium` | Edge worker, ZIP install via PowerShell `user_data` |
| `aws_cloudwatch_log_group.cribl_stream` / `cribl_edge` | 30-day retention | Container for instance logs |
| `data.http.cribl_stream_rpm` / `cribl_edge_zip` | HEAD probe | Pre-deploy validation of download URLs |

Wired in `modules/main.tf` lines 246-261. Toggled by `var.enable_cribl`.

### Stream user_data (Linux) — what it does

1. `yum update`, install/start `amazon-ssm-agent`.
2. Create `cribl` system user.
3. Download `cribl-${version}-${build}-linux-x64.rpm`, verify SHA256, `rpm -ivh`.
4. Write `/opt/cribl/local/cribl/cribl.yml` with `distributed: { mode: master, group: default }`
   and `api: { host: 0.0.0.0, port: 4200 }`.
5. `cribl boot-start enable -m systemd -u cribl`, `systemctl start cribl --no-block`.

No admin password is set. No bearer token is provisioned. No commit/deploy is
triggered. The leader comes up with default credentials (`admin/admin`).

### Edge user_data (Windows) — what it does

1. Sets local Administrator password from `var.windows_admin_password` (random_password).
2. Downloads ZIP, SHA256-verifies, expands to `C:\Program Files\Cribl`.
3. `cribl.cmd mode-managed-edge`, writes `cribl.yml` pointing at Stream leader's private IP.
4. Installs as Windows service, starts.

### Security group + IAM

`modules/security/` defines:

- `aws_security_group.cribl` — exposes ports `4200` (Web/leader) and `9997`
  (data ingest) to `var.cribl_allowed_cidrs` (home IP from Doppler).
- `aws_iam_role.cribl_instance` + instance profile — SSM agent access, CloudWatch
  Logs write.

### Variables (current)

`environment`, `enable_cribl`, `cribl_stream_instance_type`, `cribl_edge_instance_type`,
`key_pair_name`, `security_group_ids`, `subnet_ids`, `associate_public_ip_address`,
`instance_profile_name`, `linux_ami_id`, `windows_ami_id`, `windows_admin_password`,
`cribl_version` (default `4.16.1`), `cribl_build` (default `20904e45`).

### Outputs (current)

Stream/Edge instance IDs, private IPs, public IPs (when `splunk_public_access = true`),
Stream Web URL.

## Provider docs summary (`criblio/criblio`)

Source: <https://registry.terraform.io/providers/criblio/criblio/latest> via
context7 query against `/criblio/terraform-provider-criblio`.

### Authentication

Three modes:

1. **Cribl.Cloud** — OAuth2 client credentials:
   `client_id`, `client_secret`, `organization_id`, `workspace_id`, `cloud_domain`
   (default `cribl.cloud`). Honored via provider block, env vars
   (`CRIBL_CLIENT_ID`, `CRIBL_CLIENT_SECRET`, `CRIBL_ORGANIZATION_ID`,
   `CRIBL_WORKSPACE_ID`, `CRIBL_CLOUD_DOMAIN`), or `~/.cribl/credentials` profile.
2. **On-prem** — env vars only: `CRIBL_ONPREM_SERVER_URL`, `CRIBL_BEARER_TOKEN`.
   Empty provider block reads from env.
3. **Credentials file** at `~/.cribl/credentials` (ini-style; supports profiles).

For aliased Cloud + on-prem in the same root, use two `provider "criblio"` blocks
distinguished by `alias`. Submodules accept `providers = { criblio = criblio.cloud }` or
`providers = { criblio = criblio.onprem }`.

### Resources we will use

| Resource | Purpose | Notes |
| --- | --- | --- |
| `criblio_group` | Worker group (Stream or Edge), per-group config bag | `product = "stream"` or `"edge"`; `on_prem` flag |
| `criblio_pack` | Install pack from URL or local `.crbl` | `id`, `group_id`, `source` or `filename`, `spec` (semver pin) |
| `criblio_pipeline` | Function chain | `conf.functions` is the function array; each function's `conf` is `jsonencode(...)` |
| `criblio_routes` | Routing table for a group | Single resource per group; `routes` list ordered |
| `criblio_source` | Input (HTTP/TCP/Syslog/Kafka/...) | Polymorphic; exactly one `input_*` block |
| `criblio_destination` | Output (S3/Splunk HEC/Kafka/...) | Polymorphic; exactly one `output_*` block |
| `criblio_global_var` | Reusable named values/expressions per group | |
| `criblio_collector` | Pull-style collectors (S3, REST, Azure Blob, Filesystem) | See known issue below |

### Resources we will *not* use in Phase 2

- `criblio_pack_pipeline`, `criblio_pack_routes` — pack-internal resources. Out
  of scope until we manage a custom pack with internal pipelines from this repo.
- Knowledge-object resources (`criblio_lookup`, `criblio_parser`, `criblio_schema`,
  `criblio_breaker`, `criblio_regex_rule`) — defer to Phase 5 when we migrate
  the actual data flow off `user_data`.

## Provider release history and known issues

- **First release:** `v1.0.0` on 2025-05-21.
- **Latest:** `v1.23.32` on 2026-05-12. Major version is still `1`; minor cadence
  is ~5/month. Provider is officially "Preview" per upstream and visicore's
  hard pin (`= 1.20.138`) reflects that — breaking changes can land in any minor.
- **Decision:** hard-pin a specific version, mirroring visicore. Start with the
  latest stable (`= 1.23.32`) unless Phase 2 testing surfaces a regression, in
  which case roll back to the visicore-validated `1.20.138`.

### Known issues (recently closed)

| Issue | Status | Impact |
| --- | --- | --- |
| [#115](https://github.com/criblio/terraform-provider-criblio/issues/115) | closed 2026-02-18 | `criblio_collector` S3/Azure/GCS extractor schema was empty — extractors were silently destroyed on apply. Validate collector behavior against current build. |
| [#101](https://github.com/criblio/terraform-provider-criblio/issues/101) | closed 2026-02-18 | `criblio_pipeline` perpetual state drift from Optional+Computed attrs. Validate idempotency on round-trip. |
| [#17](https://github.com/criblio/terraform-provider-criblio/issues/17) | closed 2025-08-12 | Early-days `cribl_source` resource didn't work. Marker that early versions are unsafe. |
| [#139](https://github.com/criblio/terraform-provider-criblio/issues/139) | **open** | Request for write-only attribute / ephemeral resource support for `criblio_secret`. Affects how we pass bearer tokens / OAuth secrets without leaking into state. Workaround: use env vars exclusively for provider auth. |

## EC2 → criblio handoff

The two layers must run in this order:

```text
1. modules/cribl/        →  aws_instance.cribl_stream created
                            user_data runs, leader API on :4200 reaches "ready" state
                            (process up, can authenticate, no commit yet)

2. (boundary)            →  Terraform runner needs:
                            - reachable leader URL (http://<ip>:4200)
                            - authenticated bearer token for the criblio provider

3. modules/cribl-config/ →  criblio_group, criblio_pack, criblio_pipeline,
                            criblio_routes, criblio_source, criblio_destination,
                            criblio_collector, criblio_global_var resources
                            modify the leader's draft, then commit+deploy.
```

### Reachability

`splunk_public_access = true` (dev default) places the Stream instance in a
public subnet with a public IP. SG `cribl-sg` exposes port 4200 to
`var.cribl_allowed_cidrs` (home IP from Doppler `NETWORK_PUBLIC_IP_ADDRESS`).
Terraform runner on the home network reaches the leader on `:4200` directly.

If `splunk_public_access = false`, the Terraform runner must run inside the
VPC (Session Manager port forward, or a bastion). Phase 2 will assume the dev
default; non-dev tiers will need a connectivity story.

### Boot timing

`systemctl start cribl --no-block` returns immediately. The leader's API can
take 2-5 minutes to accept logins on a cold boot. Solutions:

- `time_sleep` resource between `aws_instance.cribl_stream` and the first
  `criblio_*` resource (crude but predictable).
- `null_resource` with a `local-exec` that polls `GET /api/v1/system/info` until
  HTTP 200 (preferred; mirrors visicore's `commit-deploy` chokepoint pattern).
- Both approaches must run on the Terraform runner, not on the instance, so the
  `cribl_allowed_cidrs` SG rule is the gating control.

### Bearer token provisioning

The user_data leaves the leader with default admin/admin. Phase 2 needs to:

1. Set the admin password at boot via `user_data` (write to `users.yml` or set
   via `cribl users add` CLI). Source the password from Doppler/SSM, not random.
2. After leader is reachable, mint a bearer token via `POST /api/v1/auth/login`
   with admin creds — either:
   - **Option A (simpler):** `null_resource` `local-exec` that calls the login
     endpoint and writes the token to a sensitive output / SSM Parameter Store,
     then `data.aws_ssm_parameter` reads it for `CRIBL_BEARER_TOKEN` env injection.
   - **Option B (cleaner):** generate a long-lived API token at first boot via
     user_data, write to SSM Parameter Store directly, read via `data.aws_ssm_parameter`.

Phase 2 will use Option B — it keeps the password ephemeral and the token
auditable in SSM.

## Visicore reference shape (mined, not copied)

`JacobPEvans/obsidian-visicore` at commit `6a7faecc` planned a 12-module shape:

```text
terraform/
├── lib/providers.tf          # hard pin, multi-provider declaration
├── modules/
│   ├── worker-group/         # group + routes (submodule under routes/)
│   ├── pack/                 # marketplace or custom pack with version pin
│   ├── source/               # push-style inputs
│   ├── collector/            # pull-style collectors (S3/REST/Blob/FS)
│   ├── destination/          # outputs
│   ├── pipeline/             # function chain
│   ├── lookup/               # CSV/JSON lookups (large payloads, separate)
│   ├── parser/               # reusable parsers
│   ├── schema/               # event schemas
│   ├── breaker/              # event breakers
│   ├── regex-rule/           # regex extractors
│   └── commit-deploy/        # null_resource chokepoint for commit + deploy
└── envs/                     # per-environment roots (cloud-prod, cloud-staging, onprem)
```

Key shapes worth copying:

- **`commit-deploy/` as a `null_resource` chokepoint** — the criblio provider
  does not model the Cribl "commit + deploy" action because it is an
  operation, not state. Wrap it as a `null_resource` with `triggers` keyed on
  hashes of every other module's output; `depends_on` from every other module.
  This guarantees ordering: provider resources reconcile draft → commit-deploy
  publishes → next plan reads back clean.
- **Hard-pin provider version** — `version = "= X.Y.Z"`, not `~> X.Y`. Preview
  status means breaking changes in minors.
- **Per-environment roots** — separate `envs/dev/` from `envs/prod/` so we can
  validate in one tier without touching the other.

Key shapes worth diverging from:

- **12 peer modules is too many for our scope.** This repo has one Stream
  leader and one Edge worker. Start with 6 modules (worker-group, pack,
  pipeline, route, source, destination) plus commit-deploy. Add the rest when
  data flow migrates off user_data in Phase 5.
- **Per-wave state keys** — not needed. We have one env per tier.

## Phase 2 — module layout (planned)

```text
modules/cribl-config/
├── main.tf                  # provider config (Cloud + on-prem aliases), wiring
├── variables.tf             # leader_url, bearer_token, cloud creds, enable_criblio_config
├── outputs.tf
├── worker-group/
├── pack/
├── pipeline/
├── route/
├── source/
├── destination/
└── commit-deploy/
```

Gated by `var.enable_criblio_config`, default `false`. When `false`, the entire
new module is `count = 0` no-op.

## Open questions for Phase 2 design

1. **Where do bearer tokens land?** Decision: SSM Parameter Store (`SecureString`,
   KMS-encrypted), populated by user_data, read via `data.aws_ssm_parameter`,
   exported as `TF_VAR_cribl_bearer_token` in the terragrunt inputs block
   (sensitive). Avoids token-in-state until upstream issue [#139] lands write-only attrs.
2. **Cloud vs on-prem in dev?** Decision: on-prem only for Phase 2. Cloud creds
   exist but won't be wired until a Cribl.Cloud workspace is provisioned (out
   of scope for this repo).
3. **Apply ordering with `time_sleep` vs `null_resource` poll?** Decision: poll
   in `commit-deploy/` module; no top-level `time_sleep`.
4. **Where does the admin password come from?** Decision: Doppler
   `CRIBL_ADMIN_PASSWORD` → terragrunt input → `aws_ssm_parameter` →
   instance reads via SSM at boot. Same pattern as Splunk admin password today.

## Phase 5 — decommission scope

Tracked at the issue opened in this PR. Closes when:

- All `user_data` config moves to criblio resources.
- Windows Cribl Edge resources stripped from `modules/cribl/` (instance,
  `cribl_edge_zip` data source, Windows SG rules, Windows AMI variable,
  `windows_admin_password`, `cribl_edge_instance_type`).
- `enable_criblio_config` default flipped to `true`.
- Final terragrunt plan shows only the deletions from decommission.
