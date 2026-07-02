# Provider configuration.
# Credentials come from the standard AWS credential chain (environment
# variables, shared config/credentials files, SSO, or an assumed role) —
# nothing in this repository manages or stores AWS credentials.

provider "aws" {
  region = var.aws_region
}

# criblio provider — two aliases:
#   onprem: bearer_auth against the Stream leader EC2 instance
#   cloud : OAuth2 client credentials against Cribl.Cloud
# Both aliases fall back to provider env vars (CRIBL_*) when the corresponding
# variable is empty, so callers can choose either pattern.
provider "criblio" {
  alias = "onprem"

  server_url  = var.cribl_onprem_server_url != "" ? var.cribl_onprem_server_url : null
  bearer_auth = var.cribl_onprem_bearer_token != "" ? var.cribl_onprem_bearer_token : null
}

provider "criblio" {
  alias = "cloud"

  client_id       = var.cribl_cloud_client_id != "" ? var.cribl_cloud_client_id : null
  client_secret   = var.cribl_cloud_client_secret != "" ? var.cribl_cloud_client_secret : null
  organization_id = var.cribl_cloud_organization_id != "" ? var.cribl_cloud_organization_id : null
  workspace_id    = var.cribl_cloud_workspace_id != "" ? var.cribl_cloud_workspace_id : null
  cloud_domain    = var.cribl_cloud_domain
}
