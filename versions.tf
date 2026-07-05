# Version constraints for the root module.
# OpenTofu >= 1.10 is required (the S3 backend uses native lockfile-based
# state locking, which landed in 1.10 — no DynamoDB table needed). This
# repository is developed and tested with OpenTofu only (the `tofu` CLI).

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    criblio = {
      source  = "criblio/criblio"
      version = "~> 1.23"
    }
  }
}
