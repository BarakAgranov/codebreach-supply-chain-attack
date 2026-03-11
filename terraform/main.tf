# =============================================================================
# CODEBREACH ATTACK SIMULATION LAB -- MAIN INFRASTRUCTURE
# =============================================================================
#
# This file creates the intentionally vulnerable infrastructure that simulates
# the Wiz CodeBreach attack chain (January 2026). The key vulnerability is an
# AWS CodeBuild webhook filter with an unanchored regex pattern, allowing
# unauthorized GitHub users to trigger builds and steal credentials.
#
# RESOURCES CREATED:
#   - S3 bucket for CodeBuild artifacts
#   - Secrets Manager secrets (GitHub PAT, npm token, simulated DB creds)
#   - IAM role for CodeBuild with intentionally broad permissions
#   - CodeBuild project connected to GitHub
#   - CodeBuild webhook with VULNERABLE ACTOR_ACCOUNT_ID filter
#   - Lambda function (simulates downstream resource the attacker can access)
#   - CloudTrail for detection/forensics
#
# =============================================================================

# Generate a random suffix for globally unique names (S3 buckets, etc.)
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix = random_id.suffix.hex

  # Build the VULNERABLE webhook filter pattern.
  # INTENTIONAL FLAW: No ^ or $ anchors around the user IDs.
  # This means a GitHub user ID like 226755743 will match 755743
  # because the regex engine performs substring matching.
  #
  # VULNERABLE pattern:  755743|234567
  # SECURE pattern:      ^(755743|234567)$
  #
  # The entire CodeBreach attack hinges on this single misconfiguration.
  vulnerable_actor_filter = join("|", var.trusted_github_user_ids)

  # This is what the filter SHOULD look like (we use this for comparison only)
  secure_actor_filter = "^(${join("|", var.trusted_github_user_ids)})$"
}

# =============================================================================
# S3 BUCKET -- Build Artifacts Storage
# =============================================================================
# CodeBuild writes build outputs (compiled SDK, test results, coverage reports)
# to this S3 bucket. In a real scenario, published npm packages might also
# transit through here before being pushed to the registry.
#
# SECURITY NOTE: This bucket is properly configured (private, encrypted).
# The vulnerability in this scenario is in CodeBuild's webhook filter, not S3.
# =============================================================================

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_prefix}-artifacts-${local.name_suffix}"
  force_destroy = true # Allow Terraform to delete bucket even with objects (lab only!)
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# SECRETS MANAGER -- Credentials Stored in the Build Environment
# =============================================================================
# These secrets simulate what a real CI/CD pipeline stores:
#   1. GitHub PAT for the automation bot (THIS IS THE TARGET of the attack)
#   2. npm publish token (for publishing SDK releases)
#   3. Database credentials (simulated downstream resource)
#
# CodeBuild resolves Secrets Manager references in the buildspec.yml at
# build time, injecting them as environment variables. The attacker's goal
# is to extract these from the build environment.
# =============================================================================

# SECRET 1: GitHub Automation Bot PAT
# This is the crown jewel. In the real CodeBreach attack, this token had
# admin access to the aws-sdk-js-v3 repository. Stealing it = game over.
resource "aws_secretsmanager_secret" "github_automation" {
  name                    = "${var.project_prefix}/github-automation"
  description             = "GitHub Classic PAT for the SDK automation bot. Has repo + admin:repo_hook scopes. THIS IS THE ATTACK TARGET."
  recovery_window_in_days = 0 # Immediate deletion for lab cleanup
}

resource "aws_secretsmanager_secret_version" "github_automation" {
  secret_id = aws_secretsmanager_secret.github_automation.id
  secret_string = jsonencode({
    token    = var.github_token
    username = "mega-sdk-automation-bot"
    note     = "Classic PAT with repo + admin:repo_hook. Used by CodeBuild for GitHub operations."
  })
}

# SECRET 2: npm Publish Token
# Used to publish new SDK versions to the npm registry.
# If stolen, the attacker can publish malicious SDK versions directly.
resource "aws_secretsmanager_secret" "npm_token" {
  name                    = "${var.project_prefix}/npm-publish-token"
  description             = "npm token for publishing SDK packages. If stolen, attacker can publish malicious versions."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "npm_token" {
  secret_id = aws_secretsmanager_secret.npm_token.id
  secret_string = jsonencode({
    token    = var.simulated_npm_token
    registry = "https://registry.npmjs.org"
  })
}

# SECRET 3: Simulated Database Credentials
# Represents downstream resources accessible from the CI/CD environment.
resource "aws_secretsmanager_secret" "database" {
  name                    = "${var.project_prefix}/database-credentials"
  description             = "Production database credentials. Simulates downstream resources accessible from CI/CD."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    host     = "prod-db.cluster-abc123.us-east-1.rds.amazonaws.com"
    port     = 5432
    database = "megasdk_prod"
    username = "app_user"
    password = "SIMULATED_PASSWORD_lab_only_d8f3a2b1"
  })
}

# =============================================================================
# IAM ROLE -- CodeBuild Service Role
# =============================================================================
# This IAM role is assumed by CodeBuild when executing builds. It determines
# what AWS resources the build environment can access.
#
# INTENTIONAL MISCONFIGURATION: The role has broader permissions than needed.
# A real SDK build only needs S3 write (for artifacts) and Secrets Manager
# read (for the npm token). This role also grants access to Lambda, IAM
# read, and other services -- simulating the common "just make it work"
# over-permissioning that plagues real CI/CD pipelines.
#
# SECURE ALTERNATIVE: Scope the policy to only the specific S3 bucket,
# specific secret ARNs, and CloudWatch Logs. Nothing else.
# =============================================================================

data "aws_caller_identity" "current" {}

# Trust policy: Only AWS CodeBuild can assume this role
data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  description        = "CodeBuild service role for the CodeBreach lab. INTENTIONALLY overprivileged."
}

# The overprivileged policy
data "aws_iam_policy_document" "codebuild_policy" {
  # CloudWatch Logs -- required for CodeBuild to write build logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_prefix}-*:*"]
  }

  # S3 -- for build artifacts
  statement {
    sid    = "S3Artifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  # Secrets Manager -- for resolving buildspec secrets
  # MISCONFIGURATION: Uses wildcard instead of specific secret ARNs
  statement {
    sid    = "SecretsManagerBroad"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecrets",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_prefix}/*"]
  }

  # Lambda -- overprivileged, allows invoking and listing functions
  # NOT NEEDED for an SDK build pipeline. This is the "just in case" mistake.
  statement {
    sid    = "LambdaOverprivileged"
    effect = "Allow"
    actions = [
      "lambda:ListFunctions",
      "lambda:GetFunction",
      "lambda:InvokeFunction"
    ]
    resources = ["*"]
  }

  # IAM read -- allows the build to enumerate IAM resources
  # NOT NEEDED for an SDK build. Another "troubleshooting" leftover.
  statement {
    sid    = "IAMReadOverprivileged"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:ListRoles",
      "iam:ListUsers",
      "iam:GetUser"
    ]
    resources = ["*"]
  }

  # CodeBuild -- allows the build to read its own project config
  # Used during build to resolve source credentials
  statement {
    sid    = "CodeBuildSelf"
    effect = "Allow"
    actions = [
      "codebuild:BatchGetProjects",
      "codebuild:ListProjects"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "codebuild" {
  name   = "${var.project_prefix}-codebuild-policy"
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

# =============================================================================
# CODEBUILD SOURCE CREDENTIAL
# =============================================================================
# This registers the GitHub PAT with CodeBuild so it can clone repositories
# and report build status back to GitHub. CodeBuild stores this credential
# at the account level (one per source type per account).
#
# SECURITY NOTE: Using a Classic PAT here is itself a risk. The secure
# alternative is AWS CodeConnections (formerly CodeStar Connections), which
# installs a GitHub App with scoped, short-lived tokens.
# =============================================================================

resource "aws_codebuild_source_credential" "github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}

# =============================================================================
# CODEBUILD PROJECT -- The Target Build Pipeline
# =============================================================================
# This is the core of the scenario. The CodeBuild project is configured to:
#   1. Pull source code from the GitHub repository
#   2. Execute the buildspec.yml during builds
#   3. Store build artifacts in S3
#   4. Report build status back to GitHub
#
# INTENTIONAL MISCONFIGURATION:
#   - No code signing or build approval requirements
#   - Overprivileged IAM role
#   - Secrets accessible in the build environment
#
# SECURE ALTERNATIVE:
#   - Use CodeConnections instead of PAT
#   - Enable build approval (PR Comment Approval gate)
#   - Least-privilege IAM role
#   - Code signing for all build artifacts
# =============================================================================

resource "aws_codebuild_project" "sdk_build" {
  name          = "${var.project_prefix}-sdk-build"
  description   = "CI/CD pipeline for mega-sdk-js. INTENTIONALLY VULNERABLE for CodeBreach lab."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30 # 30 minutes max

  # Source configuration: connect to GitHub
  source {
    type                = "GITHUB"
    location            = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    git_clone_depth     = 1           # Shallow clone (faster)
    buildspec           = "buildspec.yml"
    report_build_status = true
  }

  # Build environment: Amazon Linux 2 with Node.js
  environment {
    compute_type = "BUILD_GENERAL1_SMALL" # 3 GB memory, 2 vCPUs
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    # These environment variables are visible in the build.
    # The SECRETS_MANAGER type resolves the secret at build time.
    environment_variable {
      name  = "SDK_NAME"
      value = "mega-sdk-js"
      type  = "PLAINTEXT" # Visible in console and logs
    }

    environment_variable {
      name  = "GITHUB_TOKEN"
      value = "${aws_secretsmanager_secret.github_automation.name}:token"
      type  = "SECRETS_MANAGER" # Resolved at build time, masked in logs
    }

    environment_variable {
      name  = "NPM_TOKEN"
      value = "${aws_secretsmanager_secret.npm_token.name}:token"
      type  = "SECRETS_MANAGER"
    }
  }

  # Build artifacts go to S3
  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.artifacts.bucket
    path      = "builds"
    name      = "sdk-output"
    packaging = "ZIP"
  }

  # Build logs go to CloudWatch
  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${var.project_prefix}-sdk-build"
      stream_name = "build-log"
    }
  }

  depends_on = [aws_codebuild_source_credential.github]
}

# =============================================================================
# CODEBUILD WEBHOOK -- THE VULNERABILITY
# =============================================================================
# This webhook tells GitHub to notify CodeBuild when pull request events occur.
# The filter_group restricts WHICH events trigger builds.
#
# *** THIS IS THE CORE VULNERABILITY ***
#
# The ACTOR_ACCOUNT_ID filter uses a regex pattern WITHOUT ^ and $ anchors.
# This means:
#   Pattern:  755743
#   Matches:  755743       (exact match -- intended)
#   Matches:  226755743    (substring match -- NOT intended!)
#   Matches:  755743999    (substring match -- NOT intended!)
#
# SECURE FIX: Use ^(755743)$ to force exact matching.
#
# In the real CodeBreach attack, Wiz researchers exploited this exact flaw
# to bypass the ACTOR_ACCOUNT_ID filter on four AWS-managed GitHub repos,
# including the aws-sdk-js-v3 repository used by 66% of cloud environments.
# =============================================================================

resource "aws_codebuild_webhook" "sdk_webhook" {
  project_name = aws_codebuild_project.sdk_build.name
  build_type   = "BUILD"

  # Filter group 1: Trigger on pull request events from "trusted" actors
  filter_group {
    # Only trigger on PR created or updated events
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED"
    }

    # VULNERABLE FILTER: No ^ and $ anchors!
    # Any GitHub user whose numeric ID CONTAINS a trusted ID as a
    # substring will bypass this filter.
    filter {
      type    = "ACTOR_ACCOUNT_ID"
      pattern = local.vulnerable_actor_filter
    }
  }

  depends_on = [aws_codebuild_source_credential.github]
}

# =============================================================================
# LAMBDA FUNCTION -- Simulated Downstream Resource
# =============================================================================
# This Lambda function simulates a downstream resource that the CodeBuild
# role can access (because of the overprivileged IAM policy). In a real
# environment, this could be a deployment function, a release pipeline,
# or an internal API.
#
# The attacker discovers this function during post-exploitation
# reconnaissance from within the build environment.
# =============================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-PYTHON
import json

def lambda_handler(event, context):
    """
    Simulated internal deployment function.
    In the real world, this might deploy containers, update DNS,
    or trigger downstream pipelines.
    """
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Deployment function executed",
            "version": "3.42.0",
            "environment": "production",
            "internal_api_key": "SIMULATED_INTERNAL_KEY_do_not_use"
        })
    }
PYTHON
    filename = "lambda_function.py"
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_prefix}-deploy-function-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "deploy" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_prefix}-deploy-function"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DEPLOY_ENV = "production"
      SDK_BUCKET = aws_s3_bucket.artifacts.id
    }
  }
}

# =============================================================================
# CLOUDTRAIL -- Detection and Forensics
# =============================================================================
# CloudTrail logs every AWS API call. This is how defenders reconstruct
# attack timelines. We create a dedicated trail for this lab so you can
# review the attacker's actions after the exercise.
# =============================================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_prefix}-cloudtrail-${local.name_suffix}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudtrail" "lab" {
  name                          = "${var.project_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
