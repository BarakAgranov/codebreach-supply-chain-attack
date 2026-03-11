# =============================================================================
# PROVIDERS CONFIGURATION
# =============================================================================
# This file defines which Terraform providers (plugins) are required and their
# version constraints. The AWS provider manages all AWS resources. The random
# provider generates unique identifiers to avoid naming collisions.
# =============================================================================

terraform {
  # Terraform version constraint.
  # We require >= 1.11.0 for the latest HCL features and bug fixes.
  required_version = ">= 1.11.0"

  required_providers {
    # AWS provider v6.x -- the latest major version as of March 2026.
    # v6.0 introduced multi-region support via resource-level region attributes.
    # The ~> 6.30 constraint allows patch updates (6.30.x, 6.31.x, etc.)
    # but not major version jumps.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.30"
    }

    # Random provider for generating unique suffixes to avoid naming collisions.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for creating zip files (Lambda deployment packages).
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Configure the AWS provider with the lab account region.
provider "aws" {
  region = var.aws_region

  # Default tags applied to EVERY resource created by this provider.
  # This makes it easy to find and clean up all lab resources.
  default_tags {
    tags = {
      Project  = "cloud-attack-lab"
      Scenario = "codebreach"
      Warning  = "INTENTIONALLY-VULNERABLE-LAB-ONLY"
    }
  }
}
