# MITRE ATT&CK Mapping -- CodeBreach

Full technique mapping for every step of the CodeBreach attack simulation.

## Attack Technique Summary

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

## Key Observations

**Identity is the primary attack surface.** Every phase of this attack pivots through an identity system -- GitHub user IDs for the webhook bypass, GitHub PAT for repository access, and the CodeBuild IAM role for AWS access.

**Cross-service trust creates hidden blast radius.** Compromising CodeBuild (a CI/CD service) gave access to Secrets Manager, Lambda, IAM, and S3 -- plus the entire GitHub repository. One compromised service led to five others.

**Cloud-native features become weapons.** The webhook filter, buildspec override, and Secrets Manager integration are all designed features used against the defender. No exploit code was needed -- just configuration abuse.

## References

- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)
- [MITRE ATT&CK for CI/CD](https://attack.mitre.org/techniques/T1195/002/)
