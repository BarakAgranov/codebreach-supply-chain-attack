# =============================================================================
# OUTPUTS
# =============================================================================
# These values are needed during the attack phase. Some are "public"
# information the attacker discovers, others are used for verification.
# =============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project (the attacker discovers this)"
  value       = aws_codebuild_project.sdk_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.sdk_build.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild.arn
}

output "vulnerable_filter_pattern" {
  description = "The VULNERABLE ACTOR_ACCOUNT_ID filter pattern (no anchors)"
  value       = local.vulnerable_actor_filter
}

output "secure_filter_pattern" {
  description = "What the filter SHOULD look like (with anchors)"
  value       = local.secure_actor_filter
}

output "artifacts_bucket" {
  description = "S3 bucket for build artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "github_automation_secret_name" {
  description = "Name of the GitHub automation PAT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.github_automation.name
}

output "github_automation_secret_arn" {
  description = "ARN of the GitHub automation PAT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.github_automation.arn
}

output "npm_token_secret_name" {
  description = "Name of the npm token secret"
  value       = aws_secretsmanager_secret.npm_token.name
}

output "npm_token_secret_arn" {
  description = "ARN of the npm token secret in Secrets Manager"
  value       = aws_secretsmanager_secret.npm_token.arn
}

output "database_secret_name" {
  description = "Name of the database credentials secret"
  value       = aws_secretsmanager_secret.database.name
}

output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.database.arn
}

output "lambda_function_name" {
  description = "Name of the simulated deployment Lambda function"
  value       = aws_lambda_function.deploy.function_name
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail for forensics"
  value       = aws_cloudtrail.lab.name
}

output "github_owner" {
  description = "GitHub owner/username"
  value       = var.github_owner
}

output "github_repo" {
  description = "GitHub repository name"
  value       = var.github_repo
}

output "github_repo_url" {
  description = "URL of the GitHub repository"
  value       = "https://github.com/${var.github_owner}/${var.github_repo}"
}

output "webhook_url" {
  description = "The webhook URL registered with GitHub (CodeBuild endpoint)"
  value       = aws_codebuild_webhook.sdk_webhook.url
  sensitive   = true
}

output "secrets_manager_names" {
  description = "List of all Secrets Manager secret names for harvesting"
  value = [
    aws_secretsmanager_secret.github_automation.name,
    aws_secretsmanager_secret.npm_token.name,
    aws_secretsmanager_secret.database.name,
  ]
}

output "project_prefix" {
  description = "The project prefix used for resource naming"
  value       = var.project_prefix
}
