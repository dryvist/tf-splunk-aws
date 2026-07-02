# Terraform / OpenTofu Test Suite Standards

Project-internal testing convention for `tofu test` suites.
Written so it can be lifted out and shared as a standalone reference for the
community — nothing in here is repo-specific beyond the examples.

Status: living document. Pin a commit when citing.

## 1. Why these standards exist

`tofu test` is powerful but underspecified by upstream.
Teams that adopt them without a convention end up with one of three failure modes:

1. **Order-dependent failures.** A test passes in isolation, fails in the full
   suite. Almost always `override_module` leakage.
2. **Silent skip cascades.** One failure in an early file causes ten downstream
   files to skip; the green "X passed, Y failed" line hides the real signal.
3. **Mock drift.** A `mock_provider` stanza in file A drifts from one in file
   B; over time, the suite tests two different fictional providers.

This document encodes the patterns that prevent each.

## 2. Scope

Applies to any repository that runs `tofu test`. Examples
use OpenTofu syntax; everything carries to HashiCorp Terraform unmodified.

Out of scope:

- Integration tests against real cloud APIs (use Terratest, kitchen-terraform,
  or repo-specific harnesses).
- Pre-commit validation (`fmt`, `validate`, `tflint`) — covered separately.

## 3. Directory layout

```text
modules/
├── main.tf
├── variables.tf
├── outputs.tf
├── <submodule>/
└── tests/
    ├── <subject>.tftest.hcl   # one file per logical subject
    └── ...
```

Rules:

- Test files live in `tests/`, never inside individual submodules. The
  root module is the test subject; submodules are overridden.
- One file per logical subject. Filename matches what the file tests
  (`network.tftest.hcl`, `security.tftest.hcl`, `cribl_config.tftest.hcl`).
  Not by feature, not by ticket.
- No `helpers.tftest.hcl` or shared include files. `tftest` doesn't support
  includes; duplicate the `mock_provider` stanza in each file and keep them in
  sync via the synchronization check (§7).

## 4. File header convention

Every `*.tftest.hcl` file starts with this header, in this order:

1. Header comment block: one sentence describing what this file tests; one
   sentence describing what it explicitly does NOT override (the test subject).
2. `mock_provider` declarations, alphabetical by source.
3. `override_module` declarations, alphabetical by target.
4. `variables { ... }` block with shared defaults for the file.
5. `run` blocks.

Example:

```hcl
# Tests for the cribl-config module (criblio provider layer).
#
# Subject: module.cribl_config. Does NOT override that target.
# Does NOT override module.network — its real outputs (vpc_cidr_block, etc.)
# must remain populated so neighboring tftest files keep passing.

mock_provider "aws" {}
mock_provider "criblio" {
  alias = "cloud"
}
mock_provider "criblio" {
  alias = "onprem"
}
mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = ""
    }
  }
}
mock_provider "null" {}
mock_provider "random" {}
mock_provider "tls" {}

override_module {
  target = module.security
  outputs = {
    # ...
  }
}

variables {
  environment = "test"
}

run "cribl_config_disabled_by_default" {
  # ...
}
```

## 5. Override hygiene — the order-dependence trap

`override_module` declarations at the file level apply globally during a
suite-wide `tofu test` run. They do **not** isolate to the file they appear in.
This is the single most common cause of order-dependent failures.

### 5.1 Hard rules

1. **Never override `module.network`** (or any module whose outputs other test
   files assert on). Run it under `mock_provider` instead — the real module
   computes its real outputs; the mock provider returns zero-cost fake resources.
2. **Run every new test file twice**: once with `-filter=<file>`, once as part
   of the full suite. If results diverge, an `override_module` is leaking. Fix
   it before merging.
3. **The test subject is never overridden in its own file.** A file testing
   `module.foo` must not contain `override_module { target = module.foo }`.
4. **Only override what you must.** Each override is a future leak. If a test
   passes without an override, delete the override.

### 5.2 When to scope overrides to a `run` block

If a fact is true only inside one `run` block (e.g., the test asserts behavior
with a specific mocked output value), put the `override_module` inside the
`run` block, not at file scope:

```hcl
run "splunk_unreachable_triggers_alarm" {
  command = plan

  override_module {
    target = module.splunk
    outputs = {
      splunk_web_url = ""   # simulate failure
    }
  }

  assert { ... }
}
```

Run-scoped overrides cannot leak to other files.

### 5.3 Output schema must match reality

Override outputs that don't exist on the real module produce warnings, not
errors. They are still wrong: they signal that the test schema has drifted from
the module schema. Fix every "Output not found" warning before merging:

```text
Warning: Output not found: splunk_hec_url
  on tests/cribl_config.tftest.hcl line 61, in override_module:
   61:   target = module.splunk
```

Means: delete `splunk_hec_url` from the override, or add the output to
`splunk/outputs.tf` if it should exist.

## 6. Mock provider hygiene

### 6.1 Cover every required provider

If the module's `required_providers` lists eight providers, every test file
mocks eight providers. Missing one means the provider tries to authenticate
against the real backend during `plan`, fails silently, and produces `null`
outputs that cascade into assertion errors several files away.

### 6.2 Mock aliased providers separately

Each provider alias requires its own `mock_provider` block:

```hcl
mock_provider "criblio" {
  alias = "onprem"
}
mock_provider "criblio" {
  alias = "cloud"
}
```

A single un-aliased `mock_provider "criblio" {}` does not satisfy both aliases.

### 6.3 Synchronize across files

Every file's `mock_provider` block list must match. The CI check in §7 enforces
this.

### 6.4 Mock `http` data sources with defaults

```hcl
mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = ""
    }
  }
}
```

Without `defaults`, every `data "http"` lookup returns null and any
`precondition` block that asserts on `status_code` fails. The `200` default
lets URL-existence checks pass; tests that need the failure case override
per-run.

## 7. CI gate — the suite must be order-independent

Add this to pre-commit or CI:

```bash
# Full suite must pass
tofu test -no-color

# Each file must also pass in isolation. Detects override_module leakage.
for f in tests/*.tftest.hcl; do
  tofu test -filter="$f" -no-color || exit 1
done

# Mock-provider drift check: every file's mock_provider name+alias set must
# match.
first=$(ls tests/*.tftest.hcl | head -1)
diff <(grep -h 'mock_provider' tests/*.tftest.hcl | sort -u) \
     <(grep -h 'mock_provider' "$first" | sort -u) \
  || { echo "mock_provider lists drift across test files"; exit 1; }
```

The third check is intentionally strict. If a single file legitimately needs an
additional mock, add it to every file (it's a no-op when the provider isn't
used).

## 8. Run-block naming

Run blocks are assertions. Name them as such — read the run block name as a
sentence that completes "this test asserts that…":

| Good | Bad |
| --- | --- |
| `enable_cribl_defaults_to_true` | `test_1` |
| `splunk_admin_password_is_sensitive` | `password_test` |
| `ssh_disabled_by_default` | `check_ssh` |
| `network_plan_succeeds` | `plan` |

`_succeeds` / `_passes` are valid suffixes for plan-completion runs that have
no other assertion. `_returns_X` / `_is_X` / `_matches_X` / `_defaults_to_X`
are valid suffixes for value assertions.

## 9. Assertion patterns

### 9.1 Equality on a known output

```hcl
assert {
  condition     = output.vpc_cidr_block == "10.0.0.0/16"
  error_message = "vpc_cidr_block should match '10.0.0.0/16', got ${output.vpc_cidr_block}"
}
```

Interpolate the actual value into the error message. When this fires in CI,
the human reading the log needs to know what they got, not just what they
expected.

### 9.2 Existence of a complex output

```hcl
assert {
  condition     = length(module.cribl.cribl_stream_instance_id) > 0
  error_message = "cribl_stream_instance_id must be populated when enable_cribl = true"
}
```

`length()` of strings is null-safe; `!= null` checks are not, because
`null != null` is itself null in HCL.

### 9.3 Sensitivity / type-shape

```hcl
assert {
  condition     = var.cribl_onprem_bearer_token == ""
  error_message = "cribl_onprem_bearer_token must default to empty string."
}
```

`tofu test` cannot directly assert that a variable is `sensitive = true` — it
can only assert default values and behavior. Document sensitivity in the
variable's description and rely on `tofu validate` to enforce the flag.

## 10. Variable injection

Two valid patterns:

- **File-level `variables { ... }`** — defaults shared by every run in the file.
- **Run-level `variables { ... }`** — overrides for a specific run.

A run-level variable shadows the file-level one. Never use the run-level
`variables` block as the primary source — duplicate values across runs go
stale.

```hcl
variables {
  environment = "test"
  enable_cribl = true
}

run "feature_flag_off" {
  command = plan
  variables {
    enable_cribl = false   # this run only
  }
  # ...
}
```

## 11. `command = plan` vs `command = apply`

- **`plan` (default)** — fast, no resources created, `mock_provider` returns
  fake outputs. Use for assertions about config shape, defaults, and validation.
- **`apply`** — slower, materializes the mocked plan. Use only when the test
  needs to observe behavior that only manifests during apply (e.g., `for_each`
  over `apply`-time data).

Default to `plan`. Only escalate to `apply` when an assertion provably needs it.

## 12. What `tofu test` cannot do

Document these explicitly so contributors don't waste cycles fighting the tool:

1. **No real-cloud testing.** `mock_provider` returns deterministic fake data;
   integration testing requires a different harness.
2. **No cross-file state.** Each file runs independently. Helpers, fixtures,
   and constants must be duplicated.
3. **No conditional `mock_provider`.** You can't enable a mock only for some
   runs.
4. **No partial output overrides.** If you `override_module { outputs = { foo
   = "..." } }`, every other output of that module becomes null.
5. **No assertions on `sensitive` flags directly.** Only on values.

## 13. Adoption checklist

For a new repository or an existing one without these standards:

- [ ] All test files in `tests/` (or equivalent canonical path)
- [ ] Header comment block in each file naming the subject and any deliberate
      non-overrides
- [ ] Every file mocks every required provider (and every alias) — same list
      across all files
- [ ] No `override_module` against modules that other test files depend on for
      outputs
- [ ] CI gate runs both the full suite and each file in isolation; both must
      pass
- [ ] Run-block names read as assertions
- [ ] Error messages interpolate the actual observed value

## 14. Reference implementation

This document was extracted from `tf-splunk-aws/tests/`. See:

- `tests/cribl.tftest.hcl` — subject `module.cribl`, overrides every other
  module.
- `tests/cribl_config.tftest.hcl` — subject `module.cribl_config`, deliberately
  does NOT override `module.network`.
- `tests/network.tftest.hcl` — subject `module.network`, overrides every other
  module.
- `tests/security.tftest.hcl` — subject `module.security`, overrides every
  other module.

Each illustrates a different overriding pattern; together they pass both
`tofu test` (full suite) and the per-file isolation check from §7.
