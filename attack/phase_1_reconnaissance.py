"""
phase_1_reconnaissance.py -- Phase 1: Reconnaissance & Analysis

Discover the CodeBuild project configuration, analyze the webhook filter
regex vulnerability, and demonstrate the GitHub ID eclipse concept.

MITRE ATT&CK Techniques:
  - T1190: Exploit Public-Facing Application (discover public CodeBuild config)
  - T1195.002: Supply Chain Compromise (identify regex flaw)
"""
import json
import re
from typing import Any, Dict

import botocore

from config import AttackConfig
from utils import (
    console,
    format_table,
    log_event,
    mark_phase_complete,
    print_detection,
    print_error,
    print_info,
    print_phase_banner,
    print_step,
    print_success,
    print_warning,
)


def discover_codebuild_project(config: AttackConfig) -> Dict[str, Any]:
    """
    Retrieve the full CodeBuild project configuration.

    In the real attack, this information was available because the CodeBuild
    projects had public visibility enabled. Anyone could read the webhook
    filter patterns, environment variable names, and IAM role ARNs.

    MITRE: T1190 (Exploit Public-Facing Application)
    """
    print_step(1, "Discovering CodeBuild project configuration")

    cb = config.aws_session.client("codebuild")

    try:
        response = cb.batch_get_projects(
            names=[config.codebuild_project_name]
        )
    except botocore.exceptions.ClientError as exc:
        print_error(f"Failed to get CodeBuild project: {exc}")
        return {}

    projects = response.get("projects", [])
    if not projects:
        print_error(f"Project '{config.codebuild_project_name}' not found")
        return {}

    project = projects[0]

    # Extract key fields
    result = {
        "name": project.get("name", ""),
        "source_type": project.get("source", {}).get("type", ""),
        "source_location": project.get("source", {}).get("location", ""),
        "buildspec": project.get("source", {}).get("buildspec", ""),
        "service_role": project.get("serviceRole", ""),
        "environment_type": project.get("environment", {}).get("type", ""),
        "environment_image": project.get("environment", {}).get("image", ""),
        "webhook_filters": [],
        "environment_variables": [],
    }

    # Extract webhook filters
    webhook = project.get("webhook", {})
    for fg in webhook.get("filterGroups", []):
        for f in fg:
            result["webhook_filters"].append({
                "type": f.get("type", ""),
                "pattern": f.get("pattern", ""),
            })

    # Extract environment variable names (not values -- those are secret)
    for ev in project.get("environment", {}).get(
        "environmentVariables", []
    ):
        result["environment_variables"].append({
            "name": ev.get("name", ""),
            "type": ev.get("type", ""),
        })

    # Display findings
    print_success(f"Project: {result['name']}")
    print_info(f"Source: {result['source_type']} - {result['source_location']}")
    print_info(f"Buildspec: {result['buildspec']}")
    print_info(f"Role: {result['service_role'].split('/')[-1]}")

    if result["webhook_filters"]:
        rows = [
            [f["type"], f["pattern"]]
            for f in result["webhook_filters"]
        ]
        table = format_table(
            "Webhook Filters",
            ["Filter Type", "Pattern"],
            rows,
            ["bright_cyan", "bright_yellow"],
        )
        console.print(table)

    if result["environment_variables"]:
        rows = [
            [ev["name"], ev["type"]]
            for ev in result["environment_variables"]
        ]
        table = format_table(
            "Environment Variables (secrets in build)",
            ["Name", "Type"],
            rows,
            ["bright_cyan", "bright_red"],
        )
        console.print(table)

    print_detection(
        "CSPM",
        "CodeBuild project exposes configuration publicly",
    )
    print_detection(
        "CSPM",
        "CodeBuild uses Classic PAT instead of CodeConnections",
    )

    log_event(
        "success",
        "CodeBuild project configuration discovered",
        phase=1,
        step=1,
        data=result,
    )
    return result


def analyze_regex_flaw(config: AttackConfig) -> Dict[str, Any]:
    """
    Analyze the ACTOR_ACCOUNT_ID webhook filter pattern and demonstrate
    the missing anchor vulnerability.

    The pattern lacks ^ and $ anchors, meaning it performs substring
    matching instead of exact matching. This is the core CodeBreach flaw.

    MITRE: T1195.002 (Supply Chain Compromise)
    """
    print_step(2, "Analyzing webhook filter regex vulnerability")

    vuln_pattern = config.vulnerable_filter_pattern
    secure_pattern = config.secure_filter_pattern
    trusted_id = vuln_pattern.split("|")[0]

    print_info(f"Vulnerable pattern: {vuln_pattern}")
    print_info(f"Secure pattern:     {secure_pattern}")
    print_info(f"Trusted user ID:    {trusted_id}")

    # Simulate the eclipse: manufacture a 9-digit ID containing the trusted ID
    eclipse_id = "226" + trusted_id

    # Test vulnerable pattern (no anchors)
    vuln_regex = re.compile(vuln_pattern)
    vuln_match = vuln_regex.search(eclipse_id)

    # Test secure pattern (with anchors)
    secure_regex = re.compile(f"^({vuln_pattern})$")
    secure_match = secure_regex.search(eclipse_id)

    result = {
        "vulnerable_pattern": vuln_pattern,
        "secure_pattern": secure_pattern,
        "trusted_id": trusted_id,
        "eclipse_id": eclipse_id,
        "vulnerable_match": bool(vuln_match),
        "secure_match": bool(secure_match),
    }

    # Display analysis
    rows = [
        [
            eclipse_id,
            "[bright_red]MATCH (BUILD TRIGGERS!)[/bright_red]"
            if vuln_match
            else "NO MATCH",
            "[bright_green]NO MATCH (BLOCKED)[/bright_green]"
            if not secure_match
            else "MATCH",
        ],
        [
            trusted_id,
            "[bright_green]MATCH[/bright_green]",
            "[bright_green]MATCH[/bright_green]",
        ],
    ]
    table = format_table(
        "Regex Anchor Analysis",
        ["GitHub User ID", "Vulnerable Pattern", "Secure Pattern"],
        rows,
        ["bright_white", "bright_red", "bright_green"],
    )
    console.print(table)

    if vuln_match:
        print_success(
            f"VULNERABILITY CONFIRMED: ID '{eclipse_id}' bypasses the filter"
        )
        print_info(
            f"Matched substring '{vuln_match.group()}' at "
            f"position {vuln_match.start()}-{vuln_match.end()}"
        )
    else:
        print_warning("Eclipse ID did not match (unexpected)")

    print_detection(
        "CSPM",
        "ACTOR_ACCOUNT_ID filter lacks regex anchors (^$)",
    )

    log_event(
        "success",
        "Regex vulnerability analysis complete",
        phase=1,
        step=2,
        data=result,
    )
    return result


def demonstrate_eclipse(config: AttackConfig) -> Dict[str, Any]:
    """
    Demonstrate the GitHub ID eclipse concept -- how an attacker
    manufactures a GitHub user ID that contains a trusted ID as substring.

    In the real attack, Wiz sampled the GitHub ID counter by creating
    organizations, predicted when a target 9-digit ID would appear,
    and batch-created 200 GitHub App registrations to capture it.

    MITRE: T1195.002 (Supply Chain Compromise)
    """
    print_step(3, "Demonstrating GitHub ID eclipse concept")

    trusted_id = config.vulnerable_filter_pattern.split("|")[0]
    current_counter = 250000000  # Approximate as of March 2026

    # Calculate nearest future IDs containing the trusted ID
    candidates = []
    for prefix_len in range(1, 4):
        for prefix in range(10 ** (prefix_len - 1), 10**prefix_len):
            candidate = int(str(prefix) + trusted_id)
            if candidate > current_counter:
                candidates.append(candidate)

    for suffix_len in range(1, 4):
        for suffix in range(10 ** (suffix_len - 1), 10**suffix_len):
            candidate = int(trusted_id + str(suffix))
            if candidate > current_counter:
                candidates.append(candidate)

    candidates.sort()
    nearest = candidates[:5] if candidates else []

    result = {
        "trusted_id": trusted_id,
        "current_counter": current_counter,
        "nearest_eclipse_ids": [],
    }

    if nearest:
        rows = []
        for c in nearest:
            ids_away = c - current_counter
            days_away = ids_away / 200000
            rows.append([
                f"{c:,}",
                f"{ids_away:,} IDs",
                f"~{days_away:.1f} days",
            ])
            result["nearest_eclipse_ids"].append({
                "id": c,
                "ids_away": ids_away,
                "days_away": round(days_away, 1),
            })

        table = format_table(
            f"Future IDs Containing '{trusted_id}' as Substring",
            ["Target ID", "Distance", "Wait Time"],
            rows,
            ["bright_cyan", "bright_white", "bright_yellow"],
        )
        console.print(table)

    print_info("GitHub assigns ~200,000 new user IDs per day")
    print_info(
        "In the real attack, Wiz batch-created 200 GitHub Apps "
        "to capture the exact target ID"
    )
    print_success("Eclipse concept demonstrated")

    print_detection(
        "CDR",
        "New/first-seen GitHub identity triggers build",
    )
    print_detection(
        "ASPM",
        "Build triggered by unknown GitHub user",
    )

    log_event(
        "success",
        "Eclipse concept demonstrated",
        phase=1,
        step=3,
        data=result,
    )
    return result


def run_phase(config: AttackConfig) -> Dict[str, Any]:
    """
    Execute Phase 1: Reconnaissance & Analysis.

    Returns a dict with all results from this phase.
    """
    print_phase_banner(1, "RECONNAISSANCE & ANALYSIS")

    results = {}

    results["project"] = discover_codebuild_project(config)
    if not results["project"]:
        print_error("Cannot proceed: CodeBuild project not found")
        return results

    results["regex_analysis"] = analyze_regex_flaw(config)
    results["eclipse"] = demonstrate_eclipse(config)

    mark_phase_complete(1)
    return results
