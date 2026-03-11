# =============================================================================
# INPUT VARIABLES
# =============================================================================
# These variables configure the lab environment. You MUST provide values for
# variables without defaults (github_token, github_owner, etc.) in a
# terraform.tfvars file. NEVER commit terraform.tfvars to version control.
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix for all resource names (use your initials for uniqueness)"
  type        = string
  default     = "codebreach-lab"
}

# -----------------------------------------------------------------------------
# GitHub Configuration
# These variables connect CodeBuild to your GitHub repository.
# -----------------------------------------------------------------------------

variable "github_token" {
  description = "GitHub Personal Access Token (Classic) with repo and admin:repo_hook scopes. This token is stored in Secrets Manager and used by CodeBuild to clone the repo and report build status. In the attack, THIS is the credential that gets stolen."
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub username or organization that owns the target repository"
  type        = string
}

variable "github_repo" {
  description = "Name of the GitHub repository (without owner prefix)"
  type        = string
  default     = "mega-sdk-js"
}

variable "trusted_github_user_ids" {
  description = "List of trusted GitHub user IDs for the webhook ACTOR_ACCOUNT_ID filter. In the real attack, these were the IDs of AWS SDK maintainers. Use YOUR GitHub user ID here."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Simulated secrets (what the attacker will try to exfiltrate)
# -----------------------------------------------------------------------------

variable "simulated_npm_token" {
  description = "Simulated npm publish token (NOT a real token -- just for the lab)"
  type        = string
  default     = "npm_SimulatedToken_DO_NOT_USE_abc123def456"
  sensitive   = true
}
