"""
report.py -- Post-attack Markdown report generator.

Creates a structured report summarizing the attack: what was discovered,
what credentials were stolen, MITRE mappings, and remediation priorities.
"""
import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from utils import print_error, print_info, print_success


def generate_report(
    results: dict,
    config: Any = None,
    log_file: Optional[str] = None,
) -> str:
    """Generate a report from attack results dict."""
    report_dir = str(
        Path(__file__).resolve().parent.parent / "reports"
    )
    os.makedirs(report_dir, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    report_path = os.path.join(
        report_dir, f"attack-report-{timestamp}.md"
    )

    lines = [
        "# CodeBreach Attack Report",
        f"",
        f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
    ]

    # Phase 1 results
    p1 = results.get("phase1", {})
    project = p1.get("project", {})
    regex = p1.get("regex_analysis", {})
    lines.append("## Phase 1: Reconnaissance")
    lines.append(f"- **CodeBuild Project:** {project.get('name', 'N/A')}")
    lines.append(
        f"- **Vulnerable Pattern:** `{regex.get('vulnerable_pattern', 'N/A')}`"
    )
    lines.append(
        f"- **Eclipse ID Match:** {regex.get('vulnerable_match', 'N/A')}"
    )
    lines.append("")

    # Phase 2 results
    p2 = results.get("phase2", {})
    build = p2.get("build", {})
    lines.append("## Phase 2: Build Exploitation")
    lines.append(f"- **Build ID:** {build.get('build_id', 'N/A')}")
    lines.append(
        f"- **Status:** {p2.get('completion', {}).get('final_status', 'N/A')}"
    )
    lines.append("")

    # Phase 3 results
    p3 = results.get("phase3", {})
    pat = p3.get("github_pat", {})
    lines.append("## Phase 3: Credential Theft")
    lines.append(f"- **GitHub PAT:** {pat.get('token_prefix', 'N/A')}")
    lines.append(
        f"- **npm Token:** {p3.get('npm_token', {}).get('token_prefix', 'N/A')}"
    )
    lines.append(
        f"- **Database:** {p3.get('database', {}).get('host', 'N/A')}"
    )
    lines.append("")

    # Phase 4 results
    p4 = results.get("phase4", {})
    identity = p4.get("identity", {})
    lines.append("## Phase 4: GitHub Exploitation")
    lines.append(f"- **Authenticated as:** {identity.get('login', 'N/A')}")
    lines.append(f"- **Scopes:** {identity.get('scopes', 'N/A')}")
    lines.append(
        f"- **Repositories:** {len(p4.get('repositories', []))}"
    )
    lines.append("")

    # Phase 5 results
    p5 = results.get("phase5", {})
    lines.append("## Phase 5: AWS Post-Exploitation")
    lines.append(
        f"- **Lambda Functions:** {len(p5.get('lambda_functions', []))}"
    )
    lines.append(f"- **IAM Users:** {len(p5.get('iam_users', []))}")
    lines.append(f"- **S3 Buckets:** {len(p5.get('s3_buckets', []))}")
    lines.append("")

    # MITRE Mapping
    lines.append("## MITRE ATT&CK Techniques Used")
    lines.append("")
    lines.append("| Phase | Technique | ID |")
    lines.append("|-------|-----------|-----|")
    lines.append("| 1 | Exploit Public-Facing Application | T1190 |")
    lines.append("| 1 | Supply Chain Compromise | T1195.002 |")
    lines.append("| 2 | Trusted Relationship | T1199 |")
    lines.append("| 2 | Unix Shell | T1059.004 |")
    lines.append("| 3 | Unsecured Credentials | T1552.001 |")
    lines.append("| 4 | Valid Accounts: Cloud | T1078.004 |")
    lines.append("| 4 | Account Manipulation | T1098 |")
    lines.append("| 5 | Cloud Infrastructure Discovery | T1580 |")
    lines.append("| 5 | Serverless Execution | T1648 |")
    lines.append("")

    # Remediation
    lines.append("## Remediation Priorities")
    lines.append("")
    lines.append(
        "1. **Add regex anchors** to all ACTOR_ACCOUNT_ID filters"
    )
    lines.append(
        "2. **Migrate from Classic PATs** to Fine-Grained PATs or GitHub Apps"
    )
    lines.append(
        "3. **Scope CodeBuild role** to specific secret ARNs only"
    )
    lines.append(
        "4. **Enable PR Comment Approval** on CodeBuild webhooks"
    )
    lines.append(
        "5. **Remove Lambda/IAM** permissions from the build role"
    )
    lines.append("")

    content = "\n".join(lines)

    with open(report_path, "w") as f:
        f.write(content)

    return report_path


def generate_report_from_log(log_path: str) -> Optional[str]:
    """Generate a report from a structured log file."""
    if not os.path.exists(log_path):
        print_error(f"Log file not found: {log_path}")
        return None

    events = []
    try:
        with open(log_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except IOError as exc:
        print_error(f"Cannot read log file: {exc}")
        return None

    # Build a results dict from log events
    results = {
        "phase1": {},
        "phase2": {},
        "phase3": {},
        "phase4": {},
        "phase5": {},
    }

    return generate_report(results)
