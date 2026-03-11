# CodeBreach

**CI/CD Supply Chain Attack Simulation** | **AWS + GitHub** | **Intermediate-Advanced** | **Based on Real Research**

Recreate the Wiz CodeBreach attack chain (January 2026), where two missing regex characters in an AWS CodeBuild webhook filter nearly enabled complete takeover of the AWS JavaScript SDK -- used by 66% of cloud environments and the AWS Console itself.

---

## Attack Chain

```
  T+0:00  RECONNAISSANCE
  +--------------------------------------------+
  | Discover public CodeBuild configuration    |  batch-get-projects
  | Read webhook filter patterns               |  ACTOR_ACCOUNT_ID exposed
  | Identify unanchored regex flaw             |  755743|234567 (no ^ or $)
  | MITRE: T1190                               |
  +---------------------+----------------------+
                        |
  T+0:30                v
  +--------------------------------------------+
  | GITHUB ID ECLIPSE                          |
  | Sample GitHub ID counter                   |  ~200,000 new IDs per day
  | Predict when eclipse ID will appear        |  226755743 contains 755743
  | Capture target ID via batch app creation   |
  | MITRE: T1195.002                           |
  +---------------------+----------------------+
                        |
  T+1:00                v
  +--------------------------------------------+
  | TRIGGER UNAUTHORIZED BUILD                 |
  | Submit PR from manufactured identity       |  Webhook filter bypassed
  | Malicious npm dependency runs in build     |  preinstall script hook
  | Credential-dumping code executes           |  /proc/*/environ
  | MITRE: T1199, T1059.004                    |
  +---------------------+----------------------+
                        |
  T+1:05  <<< CREDENTIALS STOLEN >>>
                        |
                        v
  +--------------------------------------------+
  | CREDENTIAL THEFT                           |  Secrets Manager
  | Extract GitHub Classic PAT                 |  repo + admin:repo_hook
  | Extract npm publish token                  |  Can publish SDK releases
  | Extract database credentials               |  Downstream access
  | MITRE: T1552.001                           |
  +---------------------+----------------------+
                        |
                        v
  +--------------------------------------------+
  | GITHUB EXPLOITATION & TAKEOVER             |
  | Authenticate as automation bot             |  Full repo admin access
  | Push to main, approve PRs, add collabs    |  Supply chain game over
  | MITRE: T1078.004, T1098                    |
  +--------------------------------------------+
                        |
                        v
  +--------------------------------------------+
  | AWS POST-EXPLOITATION                      |
  | Invoke Lambda functions                    |  From overprivileged role
  | Enumerate IAM users, S3 buckets            |  Full account map
  | MITRE: T1580, T1648                        |
  +--------------------------------------------+
```

---

## The Story

MegaSDK Corp maintains a JavaScript SDK used by thousands of companies. Their CI/CD pipeline uses AWS CodeBuild with a GitHub webhook that restricts builds to trusted maintainer IDs. The filter looks correct -- but two characters are missing.

Without regex anchors (`^` and `$`), the ACTOR_ACCOUNT_ID filter performs substring matching. An attacker manufactures a GitHub user ID that contains a trusted maintainer's ID, bypasses the filter, triggers a build, and steals the GitHub Classic PAT from the build environment. With that token, they have admin access to the repository and can inject malicious code into the next SDK release.

You are about to recreate every step of this attack.

---

## Prerequisites

| Tool | Version | Check Command | Install |
|------|---------|---------------|---------|
| AWS CLI v2 | 2.x | `aws --version` | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Terraform | >= 1.11.0 | `terraform --version` | [Install guide](https://developer.hashicorp.com/terraform/install) |
| Python | >= 3.10 | `python3 --version` | [python.org](https://python.org) |
| git | Any | `git --version` | [git-scm.com](https://git-scm.com) |
| GitHub Account | Free tier | - | [github.com](https://github.com) |
| Dedicated AWS Lab Account | - | `aws sts get-caller-identity` | NEVER use production |

### Pre-Setup: GitHub Repository (Manual)

Before running setup.sh, you must create a GitHub repository manually:

1. Create a GitHub Classic PAT at https://github.com/settings/tokens with scopes: `repo`, `admin:repo_hook`, `delete_repo`
2. Create a public repo named `mega-sdk-js` with a basic package.json, buildspec.yml, and README
3. Note your GitHub numeric user ID: `curl -s https://api.github.com/users/YOUR_USERNAME | jq '.id'`

See [docs/attack_guide.md](docs/attack_guide.md) for detailed step-by-step instructions.

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/BarakAgranov/codebreach-supply-chain-attack.git
cd codebreach-supply-chain-attack

# One-command setup (checks prereqs, deploys infrastructure)
./setup.sh
# First run: creates terraform.tfvars from template -- edit it with your values, then re-run

# Activate the virtual environment
source .venv/bin/activate
cd core

# Run the attack
python main.py --auto          # Full automated attack chain
```

---

## Usage

### Execution Modes

```bash
python main.py                 # Interactive menu -- pick individual phases
python main.py --auto          # Automated -- full 5-phase attack chain
python main.py --manual        # Print commands for manual execution
```

### Logging and Reports

```bash
python main.py --auto --log              # Write structured JSONL log
python main.py --auto --log --report     # Attack + generate Markdown report
python main.py report                    # Generate report from last log
```

### Lab Status

```bash
python main.py status          # Infrastructure, credentials, progress, cost
```

---

## Cleanup

```bash
./cleanup.sh
```

The cleanup script deletes CloudWatch log groups (not managed by Terraform), runs `terraform destroy`, and cleans local artifacts. State files are preserved if destroy fails.

**Manual verification checklist:**

- [ ] No `codebreach-lab-*` CodeBuild projects
- [ ] No `codebreach-lab/*` Secrets Manager secrets
- [ ] No `codebreach-lab-*` S3 buckets
- [ ] No `codebreach-lab-*` Lambda functions
- [ ] No `codebreach-lab-*` IAM roles
- [ ] Delete the `mega-sdk-js` GitHub repository
- [ ] Revoke the lab PAT at https://github.com/settings/tokens

---

## MITRE ATT&CK Mapping

| Step | Technique | ID | Tactic |
|------|-----------|-----|--------|
| Discover CodeBuild config | Exploit Public-Facing App | T1190 | Initial Access |
| Identify regex flaw | Supply Chain Compromise | T1195.002 | Initial Access |
| Trigger unauthorized build | Trusted Relationship | T1199 | Initial Access |
| Execute build commands | Unix Shell | T1059.004 | Execution |
| Extract secrets | Unsecured Credentials | T1552.001 | Credential Access |
| Authenticate with PAT | Valid Accounts: Cloud | T1078.004 | Privilege Escalation |
| Demonstrate admin access | Account Manipulation | T1098 | Persistence |
| Enumerate AWS resources | Cloud Infrastructure Discovery | T1580 | Discovery |
| Invoke Lambda | Serverless Execution | T1648 | Execution |

Full details: [detection/mitre_mapping.md](detection/mitre_mapping.md)

## CNAPP Detection Mapping

| Step | Component | Detection | Severity |
|------|-----------|-----------|----------|
| Public CodeBuild config | **CSPM** | Project exposes configuration | High |
| Unanchored regex filter | **CSPM** | ACTOR_ACCOUNT_ID allows substring bypass | Critical |
| Build with override | **CDR** | Buildspec modified at execution time | Critical |
| Credential dump in build | **CWP** | Process memory scan detected | Critical |
| Secrets Manager access | **CDR** + **DSPM** | Bulk GetSecretValue from CI/CD | High |
| GitHub PAT from unusual IP | **CDR** | Automation creds used externally | Critical |
| Repo admin changes | **ASPM** | Permissions changed outside workflow | Critical |
| Overprivileged build role | **CIEM** | Lambda + IAM access unnecessary | Medium |

Full details: [detection/cnapp_mapping.md](detection/cnapp_mapping.md)

---

## Cost Estimate

| Resource | Hourly Cost | Notes |
|----------|-------------|-------|
| IAM roles, policies | Free | |
| S3 buckets | < $0.01 | Minimal storage |
| Lambda function | < $0.01 | Invoked a few times |
| Secrets Manager (3 secrets) | ~$0.04/hr | $0.40/secret/month |
| CodeBuild (per build) | ~$0.01 | BUILD_GENERAL1_SMALL |
| CloudTrail | ~$0.01/hr | First trail mgmt events free |
| **Total** | **~$0.06/hr** | **~$1.50/day** |

---

## Project Structure

```
codebreach-supply-chain-attack/
+-- README.md                        # This file
+-- setup.sh                         # One-command setup (safe to re-run)
+-- cleanup.sh                       # Complete teardown
+-- requirements.txt                 # Python dependencies
+-- terraform/                       # Infrastructure as code
|   +-- providers.tf                 # Provider versions
|   +-- variables.tf                 # Input variables
|   +-- main.tf                      # All AWS resources
|   +-- outputs.tf                   # Values for attack scripts
|   +-- terraform.tfvars.example     # Example variable values
+-- core/                            # Lab management tooling
|   +-- main.py                      # Entry point (interactive/auto/manual)
|   +-- config.py                    # Terraform output bridge
|   +-- utils.py                     # Output formatting, logging, retry
|   +-- status.py                    # Lab environment checker
|   +-- report.py                    # Post-attack report generator
+-- attack/                          # Attack phase scripts
|   +-- phase_1_reconnaissance.py    # CodeBuild discovery, regex analysis
|   +-- phase_2_build_exploit.py     # Trigger build, retrieve logs
|   +-- phase_3_credential_theft.py  # Secrets Manager exfiltration
|   +-- phase_4_github_exploitation.py  # PAT auth, repo takeover demo
|   +-- phase_5_post_exploitation.py # Lambda, IAM, S3 from build role
+-- detection/                       # Detection mapping
|   +-- mitre_mapping.md             # MITRE ATT&CK mapping
|   +-- cnapp_mapping.md             # CNAPP component mapping
+-- docs/                            # Educational documentation
|   +-- attack_guide.md              # Full manual walkthrough
|   +-- concepts.md                  # Cloud concepts explained
|   +-- attack_narrative.md          # Incident report timeline
|   +-- real_world_examples.md       # Similar real-world breaches
+-- logs/                            # Structured attack logs (runtime)
+-- reports/                         # Generated reports (runtime)
```

---

## Lessons from the Real Attack

1. **Two characters can break everything.** The entire attack chain hinged on missing `^` and `$` in a regex pattern. No exploit code, no zero-day -- just a configuration oversight.
2. **CI/CD is the new perimeter.** The build pipeline had access to credentials, cloud resources, and the ability to modify released software. Securing CI/CD is as critical as securing production.
3. **Classic PATs are weapons.** A single Classic PAT with `repo` scope grants access to every repository the user can see. Fine-Grained PATs and GitHub Apps eliminate this blast radius.
4. **Overpermissioned build roles compound the damage.** The CodeBuild role did not need Lambda, IAM, or broad Secrets Manager access. Least privilege would have limited the attacker to only the npm token.
5. **Prevention beats detection.** A CSPM alert about the unanchored regex or public project visibility would have prevented everything. By the time CDR detects the attack, credentials are already stolen.

---

## Educational Resources

- [docs/attack_guide.md](docs/attack_guide.md) -- Complete educational walkthrough with flag-by-flag explanations
- [docs/concepts.md](docs/concepts.md) -- Every cloud concept explained from scratch
- [docs/attack_narrative.md](docs/attack_narrative.md) -- The full attack story as an incident report
- [docs/real_world_examples.md](docs/real_world_examples.md) -- 6 real breaches using similar techniques
- [Wiz: CodeBreach](https://www.wiz.io/blog/codebreach) -- The original research this lab is based on
- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)
- [AWS CodeBuild Security Best Practices](https://docs.aws.amazon.com/codebuild/latest/userguide/security-best-practices.html)
