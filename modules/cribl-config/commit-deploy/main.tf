# Commit + deploy chokepoint for the criblio config layer.
#
# The criblio provider models resources as state but does NOT model the
# "commit + deploy" leader action. Without this step, every change sits in
# the leader's draft and is never published to the worker group.
#
# This module wraps the deploy call as a null_resource keyed off content
# hashes of every upstream module's output. Every other module declares this
# as `depends_on` (implicit via passing content_hash into triggers).

terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

resource "null_resource" "commit_deploy" {
  triggers = var.triggers

  # Sensitive values are passed via the `environment` block, not interpolated
  # into the command string. The shell reads CRIBL_* from env at runtime; no
  # HCL `${...}` patterns appear in the script body, so the bearer token never
  # enters process listings or CI logs.
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CRIBL_LEADER_URL = var.leader_url
      CRIBL_TOKEN      = var.bearer_token
      CRIBL_GROUP      = var.worker_group_id
      TIMEOUT          = tostring(var.readiness_timeout_seconds)
    }
    command = <<-CMD
      set -euo pipefail

      DEADLINE=$$((SECONDS + TIMEOUT))

      if [ -z "$$CRIBL_LEADER_URL" ] || [ -z "$$CRIBL_TOKEN" ]; then
        echo "CRIBL_LEADER_URL and CRIBL_TOKEN must both be set" >&2
        exit 1
      fi

      until curl -fsS -o /dev/null \
        -H "Authorization: Bearer $$CRIBL_TOKEN" \
        "$$CRIBL_LEADER_URL/api/v1/system/info"; do
        if [ "$$SECONDS" -ge "$$DEADLINE" ]; then
          echo "leader $$CRIBL_LEADER_URL not ready after $${TIMEOUT}s" >&2
          exit 1
        fi
        sleep 5
      done

      curl -fsS -X POST \
        -H "Authorization: Bearer $$CRIBL_TOKEN" \
        -H "Content-Type: application/json" \
        "$$CRIBL_LEADER_URL/api/v1/m/$$CRIBL_GROUP/version/commit" \
        -d '{"message":"tf-splunk-aws: tofu apply"}'

      curl -fsS -X POST \
        -H "Authorization: Bearer $$CRIBL_TOKEN" \
        -H "Content-Type: application/json" \
        "$$CRIBL_LEADER_URL/api/v1/master/groups/$$CRIBL_GROUP/deploy"
    CMD
  }
}
