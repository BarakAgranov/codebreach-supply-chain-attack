"""
status.py -- Lab environment status checker.

Shows the current state of the lab: infrastructure, credentials,
attack progress, and environment health.
"""
import json
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

import boto3
import botocore

from utils import (
    console,
    get_completed_phases,
    print_error,
    print_info,
    print_success,
    print_warning,
)

TERRAFORM_DIR = str(Path(__file__).resolve().parent.parent / "terraform")


def _check_mark(ok: bool) -> str:
    return (
        "[bright_green]OK[/bright_green]"
        if ok
        else "[bright_red]--[/bright_red]"
    )


def check_infrastructure() -> Dict[str, Any]:
    """Check if Terraform infrastructure is deployed."""
    result = {"deployed": False, "resource_count": 0, "deploy_time": None}

    tfstate_path = Path(TERRAFORM_DIR) / "terraform.tfstate"
    if not tfstate_path.exists():
        return result

    try:
        with open(tfstate_path) as f:
            state = json.load(f)
        resources = state.get("resources", [])
        result["deployed"] = len(resources) > 0
        result["resource_count"] = len(resources)

        mtime = os.path.getmtime(tfstate_path)
        result["deploy_time"] = datetime.fromtimestamp(mtime).strftime(
            "%Y-%m-%d %H:%M:%S"
        )
        result["hours_running"] = round((time.time() - mtime) / 3600, 1)
        result["estimated_cost"] = f"${result['hours_running'] * 0.05:.2f}"
    except (json.JSONDecodeError, IOError):
        pass

    return result


def check_aws_credentials() -> Dict[str, Any]:
    """Check if AWS credentials are valid."""
    result = {"valid": False, "account_id": None, "identity": None}
    try:
        sts = boto3.client("sts")
        identity = sts.get_caller_identity()
        result["valid"] = True
        result["account_id"] = identity["Account"]
        result["identity"] = identity["Arn"]
    except Exception:
        pass
    return result


def check_attack_progress() -> Dict[str, Any]:
    """Detect which attack phases have been run."""
    progress = get_completed_phases()
    return {
        "phase1_recon": progress.get("phase1", False),
        "phase2_build": progress.get("phase2", False),
        "phase3_creds": progress.get("phase3", False),
        "phase4_github": progress.get("phase4", False),
        "phase5_postex": progress.get("phase5", False),
    }


def check_python_env() -> Dict[str, Any]:
    """Check Python environment health."""
    import sys

    result = {
        "python_version": sys.version.split()[0],
        "in_venv": sys.prefix != sys.base_prefix,
    }
    for pkg in ["boto3", "rich", "requests"]:
        try:
            mod = __import__(pkg)
            result[f"{pkg}_version"] = getattr(mod, "__version__", "installed")
        except ImportError:
            result[f"{pkg}_version"] = "MISSING"
    return result


def check_log_files() -> Dict[str, Any]:
    """Check for existing log files."""
    log_dir = Path(__file__).resolve().parent.parent / "logs"
    result = {"log_dir_exists": log_dir.exists(), "log_count": 0, "latest": None}
    if log_dir.exists():
        logs = sorted(log_dir.glob("*.jsonl"), reverse=True)
        result["log_count"] = len(logs)
        if logs:
            result["latest"] = logs[0].name
    return result


def run_status() -> Dict[str, Any]:
    """Run all status checks and display results."""
    from rich.table import Table
    from rich import box

    console.print()
    console.print(
        "[bold bright_white]Lab Status[/bold bright_white]",
        style="underline",
    )
    console.print()

    all_status = {}

    creds = check_aws_credentials()
    all_status["aws_credentials"] = creds

    infra = check_infrastructure()
    all_status["infrastructure"] = infra

    progress = check_attack_progress()
    all_status["attack_progress"] = progress

    pyenv = check_python_env()
    all_status["python_env"] = pyenv

    logs = check_log_files()
    all_status["logs"] = logs

    table = Table(box=box.SIMPLE, show_header=False, padding=(0, 2))
    table.add_column("Check", style="bright_cyan", width=28)
    table.add_column("Status", style="white")

    # AWS
    table.add_row(
        "AWS Credentials",
        f"{_check_mark(creds['valid'])}  "
        f"{creds.get('identity', 'Not configured')}",
    )
    table.add_row("Account ID", creds.get("account_id", "N/A"))

    # Infrastructure
    table.add_row(
        "Infrastructure",
        f"{_check_mark(infra['deployed'])}  "
        + (
            f"{infra['resource_count']} resources"
            if infra["deployed"]
            else "Not deployed"
        ),
    )
    if infra.get("hours_running"):
        table.add_row(
            "Running Since",
            f"{infra['deploy_time']}  "
            f"({infra['hours_running']}h, ~{infra['estimated_cost']})",
        )

    # Attack Progress
    phases = [
        ("P1:Recon", progress.get("phase1_recon", False)),
        ("P2:Build", progress.get("phase2_build", False)),
        ("P3:Creds", progress.get("phase3_creds", False)),
        ("P4:GitHub", progress.get("phase4_github", False)),
        ("P5:PostEx", progress.get("phase5_postex", False)),
    ]
    phase_str = "  ".join(
        f"[bright_green]{name}[/bright_green]" if done else f"[dim]{name}[/dim]"
        for name, done in phases
    )
    table.add_row("Attack Progress", phase_str)

    # Python
    venv_str = (
        "Active"
        if pyenv["in_venv"]
        else "[bright_red]Not in venv[/bright_red]"
    )
    table.add_row(
        "Python Environment",
        f"{_check_mark(pyenv['in_venv'])}  "
        f"Python {pyenv['python_version']}  ({venv_str})",
    )
    table.add_row(
        "Dependencies",
        f"boto3={pyenv.get('boto3_version', '?')}  "
        f"rich={pyenv.get('rich_version', '?')}  "
        f"requests={pyenv.get('requests_version', '?')}",
    )

    if logs["log_count"] > 0:
        table.add_row(
            "Log Files",
            f"{logs['log_count']} log(s), latest: {logs['latest']}",
        )

    console.print(table)
    console.print()

    return all_status
