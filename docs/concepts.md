# Cloud Concepts -- CodeBreach Scenario

Every cloud concept you encounter in this scenario, explained from scratch.

## AWS CodeBuild

AWS CodeBuild is a fully managed CI/CD (Continuous Integration / Continuous Delivery) service. When developers push code to a repository, CodeBuild automatically builds, tests, and packages it. A CodeBuild "project" defines where to get source code (GitHub, S3, etc.), what commands to run (the buildspec), what IAM role to use, and where to store outputs.

## Buildspec

A buildspec (build specification) is a YAML file named `buildspec.yml` that tells CodeBuild what commands to run. It has four phases: `install` (set up dependencies), `pre_build` (preparation), `build` (compile/test), and `post_build` (package). Environment variables, including secrets from Secrets Manager, are resolved before the build starts.

## Webhook Filters

When you connect CodeBuild to GitHub, a webhook notifies CodeBuild of repository events (pushes, pull requests). Filter groups control which events actually trigger builds. The `ACTOR_ACCOUNT_ID` filter restricts builds to specific GitHub user IDs using regular expression patterns.

## Regular Expressions (Regex)

Regular expressions are patterns that describe sets of strings. In CodeBuild webhook filters, regex determines which GitHub user IDs are allowed. Two critical characters are **anchors**: `^` matches the start of a string, `$` matches the end. Without anchors, the pattern searches anywhere *within* the string (substring matching). This is the core vulnerability in CodeBreach.

## GitHub User IDs

Every GitHub account (user, organization, or app) receives a sequential numeric ID from a shared counter. IDs are never recycled or changed. As of 2025-2026, new accounts get 9-digit IDs. Because IDs are sequential, an attacker can predict when a specific ID will be assigned.

## GitHub Personal Access Tokens (PATs)

PATs are credentials that authenticate GitHub API requests. **Classic PATs** grant broad access: the `repo` scope gives full read/write to ALL repositories the user can access. **Fine-Grained PATs** (newer) allow per-repository scoping and mandatory expiration. CodeBreach exploits the broad scope of Classic PATs.

## AWS Secrets Manager

Secrets Manager stores and retrieves sensitive values (database passwords, API keys, tokens). CodeBuild can reference secrets in the buildspec using the `SECRETS_MANAGER` environment variable type. At build time, CodeBuild resolves the reference and injects the secret value as an environment variable.

## IAM Roles and Service Roles

IAM (Identity and Access Management) roles define what permissions an AWS service has. A CodeBuild "service role" is the IAM role that CodeBuild assumes when running builds. If the role has broad permissions, any code running in the build inherits those permissions.

## Lambda Functions

AWS Lambda runs code without provisioning servers. You upload a function, and AWS executes it on demand. Each function has an "execution role" that determines what AWS resources the function can access. In this scenario, the CodeBuild role can invoke Lambda functions -- an unnecessary permission for an SDK build pipeline.

## CloudTrail

CloudTrail logs every AWS API call made in your account: who called what, when, from where. It is the primary audit trail for detecting attacks. In this scenario, CloudTrail records the attacker's API calls (BatchGetProjects, GetSecretValue, Invoke) with timestamps and source IPs.

## Supply Chain Attacks

A supply chain attack compromises a software component that many others depend on. Instead of attacking one target, the attacker poisons a shared dependency (like an SDK) and the malicious code propagates to every application using that dependency. CodeBreach targets the build pipeline that produces the SDK -- making it a supply chain attack at the CI/CD level.
