terraform {
  # 1.11+ is required for write-only arguments (redpanda_user.password_wo).
  required_version = ">= 1.11.0"

  required_providers {
    redpanda = {
      source  = "redpanda-data/redpanda"
      version = "~> 2.5"
    }
  }

  # Partial configuration: bucket/key/region come from envs/<env>.s3.tfbackend
  # so each environment gets its own isolated state file.
  backend "s3" {}
}

# Credentials are read from REDPANDA_CLIENT_ID / REDPANDA_CLIENT_SECRET.
provider "redpanda" {}
