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

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-CMD
      set -euo pipefail

      LEADER="${var.leader_url}"
      TOKEN="${var.bearer_token}"
      GROUP="${var.worker_group_id}"
      DEADLINE=$((SECONDS + ${var.readiness_timeout_seconds}))

      if [ -z "$LEADER" ] || [ -z "$TOKEN" ]; then
        echo "leader_url and bearer_token are required" >&2
        exit 1
      fi

      until curl -fsS -o /dev/null \
        -H "Authorization: Bearer $TOKEN" \
        "$LEADER/api/v1/system/info"; do
        if [ $SECONDS -ge $DEADLINE ]; then
          echo "leader $LEADER not ready after ${var.readiness_timeout_seconds}s" >&2
          exit 1
        fi
        sleep 5
      done

      curl -fsS -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$LEADER/api/v1/m/$GROUP/version/commit" \
        -d '{"message":"tf-splunk-aws: terraform apply"}'

      curl -fsS -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$LEADER/api/v1/master/groups/$GROUP/deploy"
    CMD
  }
}
