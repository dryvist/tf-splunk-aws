# dev environment.
# Only values that differ from the variable defaults are set here. Secrets and
# operator IPs come from the environment, not this file:
#   TF_VAR_splunk_admin_password  (optional — generated when unset)
#   TF_VAR_admin_ip_cidrs         e.g. '["203.0.113.7/32"]'

environment = "dev"

# Deploy both workloads in dev so either pipeline can be exercised.
enable_splunk = true
enable_cribl  = true

# Dev is operated over the internet: public IPs + allowlisted access.
splunk_public_access = true

# Cost guardrail: stop anything running longer than 24h (hourly sweep).
enable_auto_stop  = true
max_runtime_hours = 24

# Credential-less start/stop from the Actions tab. Set the repository slug
# after the corporate transfer, then flip this on.
enable_github_summon = false
# github_repository  = "<owner>/tf-splunk-aws"
