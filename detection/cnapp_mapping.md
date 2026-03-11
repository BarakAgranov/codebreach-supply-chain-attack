# CNAPP Detection Mapping -- CodeBreach

What a Cloud-Native Application Protection Platform (Prisma Cloud / Cortex Cloud) would detect at each stage of the CodeBreach attack.

## Detection Summary

| Step | Component | Detection Description | Severity | What the SOC Would See | Remediation |
|------|-----------|----------------------|----------|----------------------|-------------|
| 1 | **CSPM** | CodeBuild project exposes configuration | High | Posture alert: CI/CD project readable externally | Set project visibility to PRIVATE |
| 1 | **CSPM** | CodeBuild uses Classic PAT auth | Medium | Posture alert: use CodeConnections instead | Migrate to GitHub App via CodeConnections |
| 2 | **CSPM** | Webhook ACTOR_ACCOUNT_ID filter lacks anchors | Critical | Posture alert: regex allows substring bypass | Add ^ and $ anchors to all ID filters |
| 3 | **CDR** | Build triggered by unknown GitHub actor | High | Identity alert: first-seen actor in CI/CD pipeline | Enable PR Comment Approval gate |
| 4 | **CDR** | Build uses buildspec override | Critical | Runtime alert: build commands modified at execution | Disable buildspec overrides in project config |
| 4 | **ASPM** | Buildspec changed outside PR workflow | Critical | Pipeline alert: unauthorized pipeline modification | Require signed buildspecs |
| 5 | **CWP** | Process memory scan in build container | Critical | Workload alert: credential dumping detected | Enable memory protections in build images |
| 5 | **CDR** | GetSecretValue from CI/CD context | High | Data alert: secrets accessed from build | Scope IAM role to specific secret ARNs only |
| 5 | **DSPM** | Bulk secret retrieval from SM | Critical | Data alert: multiple secrets accessed rapidly | Alert on >1 secret access per build |
| 6 | **CDR** | GitHub API calls from unusual IP | Critical | Identity alert: automation account used externally | IP-restrict automation token usage |
| 7 | **ASPM** | Collaborator added by automation account | Critical | Pipeline alert: repo permissions changed | Require 2FA for admin operations |
| 8 | **CIEM** | CodeBuild role has excessive permissions | Medium | Permission alert: Lambda + IAM access unnecessary | Remove Lambda/IAM from build role |
| 8 | **CDR** | Lambda invoked from CodeBuild context | High | Resource alert: cross-service access from CI/CD | Remove Lambda invoke from build policy |

## Detection by CNAPP Component

### CSPM (Cloud Security Posture Management)
- Public CodeBuild project visibility
- Classic PAT authentication instead of CodeConnections
- Unanchored regex in ACTOR_ACCOUNT_ID filter
- Overprivileged CodeBuild service role

### CDR (Cloud Detection and Response)
- Build triggered by unknown/first-seen GitHub actor
- Buildspec override in build execution
- GetSecretValue calls from CI/CD context
- GitHub API calls from unusual IP with bot credentials
- Lambda invocation from CodeBuild execution context

### CWP (Cloud Workload Protection)
- Process memory scanning in build container
- Credential dumping detected in workload

### CIEM (Cloud Infrastructure Entitlement Management)
- CodeBuild role has Lambda invoke and IAM read permissions
- Service role has broad Secrets Manager access (wildcard)

### DSPM (Data Security Posture Management)
- GitHub PAT detected in Secrets Manager access
- Bulk secret retrieval pattern

### ASPM (Application Security Posture Management)
- Buildspec changed outside normal PR workflow
- Repository collaborator added outside normal process
