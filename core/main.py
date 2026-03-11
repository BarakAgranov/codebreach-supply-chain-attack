#!/usr/bin/env python3
"""
main.py -- CodeBreach: CI/CD Supply Chain Attack Simulation Launcher

Modes:
  python main.py              Interactive menu
  python main.py --auto       Full automated attack chain
  python main.py --manual     Deploy infra + print manual commands
  python main.py status       Show lab environment status
  python main.py report       Generate report from last log file

Flags:
  --log            Write structured log to logs/ directory
  --report         Generate Markdown report after attack completes
"""
import argparse
import json
import sys
from pathlib import Path

# Set up sys.path so core/ and attack/ modules can import each other
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "attack"))

from rich.panel import Panel
from rich.prompt import IntPrompt
from rich import box

from config import AttackConfig
from utils import (
    console,
    format_table,
    init_logging,
    close_logging,
    get_completed_phases,
    print_error,
    print_info,
    print_success,
    print_warning,
)

# =============================================================================
# Constants
# =============================================================================

BANNER = r"""
[bright_red]   ____          _      ____                      _
  / ___|___   __| | ___| __ ) _ __ ___  __ _  ___| |__
 | |   / _ \ / _` |/ _ \  _ \| '__/ _ \/ _` |/ __| '_ \
 | |__| (_) | (_| |  __/ |_) | | |  __/ (_| | (__| | | |
  \____\___/ \__,_|\___|____/|_|  \___|\__,_|\___|_| |_|
[/bright_red]
[dim]Based on Wiz Research (Jan 2026): Two missing regex characters[/dim]
[dim]nearly compromised every AWS account on Earth[/dim]
"""

TERRAFORM_DIR = str(Path(__file__).resolve().parent.parent / "terraform")
TOTAL_PHASES = 5


# =============================================================================
# Terraform Helpers
# =============================================================================


def terraform_is_deployed() -> bool:
    """Check if Terraform state exists with resources."""
    tfstate = Path(TERRAFORM_DIR) / "terraform.tfstate"
    if not tfstate.exists():
        return False
    try:
        with open(tfstate) as f:
            state = json.load(f)
        return len(state.get("resources", [])) > 0
    except (json.JSONDecodeError, IOError):
        return False


# =============================================================================
# Interactive Mode
# =============================================================================


def run_interactive(config: AttackConfig) -> dict:
    """Run in interactive menu mode. Returns combined results."""
    import phase_1_reconnaissance as p1
    import phase_2_build_exploit as p2
    import phase_3_credential_theft as p3
    import phase_4_github_exploitation as p4
    import phase_5_post_exploitation as p5
    import status as status_mod

    all_results = {}

    while True:
        console.print()
        console.print(
            Panel(
                "[bright_white]Attack Phases[/bright_white]\n\n"
                "  [bright_cyan]1[/bright_cyan]  Phase 1: Reconnaissance "
                "(CodeBuild config, regex analysis, eclipse)\n"
                "  [bright_red]2[/bright_red]  Phase 2: Build Exploitation "
                "(trigger build, extract logs)\n"
                "  [bright_yellow]3[/bright_yellow]  Phase 3: Credential Theft "
                "(Secrets Manager exfiltration)\n"
                "  [bright_magenta]4[/bright_magenta]  Phase 4: GitHub Exploitation "
                "(PAT auth, repo takeover demo)\n"
                "  [bright_green]5[/bright_green]  Phase 5: AWS Post-Exploitation "
                "(Lambda, IAM, S3 from build role)\n\n"
                "  [bright_white]6[/bright_white]  Run ALL phases sequentially\n"
                "  [dim]7[/dim]  View current config\n"
                "  [dim]8[/dim]  Lab status\n"
                "  [dim]0[/dim]  Exit",
                title="[bold]CodeBreach -- CI/CD Supply Chain Attack[/bold]",
                border_style="bright_white",
                box=box.ROUNDED,
            )
        )

        try:
            choice = IntPrompt.ask(
                "\n  Select an option",
                choices=["0", "1", "2", "3", "4", "5", "6", "7", "8"],
                default=6,
            )
        except KeyboardInterrupt:
            console.print("\n  Exiting.")
            break

        try:
            if choice == 0:
                break
            elif choice == 1:
                all_results["phase1"] = p1.run_phase(config)
            elif choice == 2:
                all_results["phase2"] = p2.run_phase(config)
            elif choice == 3:
                all_results["phase3"] = p3.run_phase(config)
            elif choice == 4:
                all_results["phase4"] = p4.run_phase(config)
            elif choice == 5:
                all_results["phase5"] = p5.run_phase(config)
            elif choice == 6:
                all_results = run_all_phases(config)
            elif choice == 7:
                config.print_config_summary()
            elif choice == 8:
                status_mod.run_status()
        except RuntimeError as exc:
            print_error(str(exc))
        except Exception as exc:
            print_error(f"Unexpected error: {exc}")
            console.print("[dim]  Returning to menu...[/dim]")

        # Check if all phases are now complete
        completed = get_completed_phases()
        if all(completed.get(f"phase{i}") for i in range(1, TOTAL_PHASES + 1)):
            console.print()
            console.print(
                Panel(
                    "[bold bright_green]ALL PHASES COMPLETE[/bold bright_green]",
                    border_style="bright_green",
                    box=box.DOUBLE,
                )
            )
            print_warning(
                "Run ./cleanup.sh when done, or select 0 to exit."
            )

    return all_results


# =============================================================================
# Automated Mode
# =============================================================================


def run_all_phases(config: AttackConfig) -> dict:
    """Run all attack phases sequentially."""
    import phase_1_reconnaissance as p1
    import phase_2_build_exploit as p2
    import phase_3_credential_theft as p3
    import phase_4_github_exploitation as p4
    import phase_5_post_exploitation as p5

    console.print(
        Panel(
            "[bold bright_red]FULL ATTACK CHAIN[/bold bright_red]\n"
            "[dim]Running all 5 phases sequentially...[/dim]",
            border_style="bright_red",
            box=box.DOUBLE,
        )
    )

    all_results = {}

    # Phase 1: Reconnaissance
    all_results["phase1"] = p1.run_phase(config)

    # Phase 2: Build Exploitation
    all_results["phase2"] = p2.run_phase(config)

    # Phase 3: Credential Theft
    all_results["phase3"] = p3.run_phase(config)

    # Phase 4: GitHub Exploitation (requires stolen PAT from Phase 3)
    if config.stolen_github_pat:
        all_results["phase4"] = p4.run_phase(config)
    else:
        print_error(
            "Skipping Phase 4: GitHub PAT not obtained in Phase 3"
        )

    # Phase 5: AWS Post-Exploitation
    all_results["phase5"] = p5.run_phase(config)

    print_attack_summary(all_results)
    return all_results


def print_attack_summary(results: dict) -> None:
    """Print a summary table of the full attack."""
    console.print()
    console.print(
        Panel(
            "[bold bright_green]ATTACK COMPLETE[/bold bright_green]",
            border_style="bright_green",
            box=box.DOUBLE,
            expand=True,
        )
    )

    rows = []

    p1 = results.get("phase1", {})
    project = p1.get("project", {})
    rows.append([
        "Phase 1",
        "Reconnaissance",
        f"Project: {project.get('name', 'N/A')}",
    ])

    p2 = results.get("phase2", {})
    build = p2.get("build", {})
    rows.append([
        "Phase 2",
        "Build Exploitation",
        f"Build #{build.get('build_number', 'N/A')}",
    ])

    p3 = results.get("phase3", {})
    pat = p3.get("github_pat", {})
    rows.append([
        "Phase 3",
        "Credential Theft",
        f"GitHub PAT: {pat.get('token_prefix', 'N/A')}",
    ])

    p4 = results.get("phase4", {})
    identity = p4.get("identity", {})
    repos = p4.get("repositories", [])
    rows.append([
        "Phase 4",
        "GitHub Exploitation",
        f"User: {identity.get('login', 'N/A')}, "
        f"{len(repos)} repos",
    ])

    p5 = results.get("phase5", {})
    lambdas = p5.get("lambda_functions", [])
    users = p5.get("iam_users", [])
    rows.append([
        "Phase 5",
        "AWS Post-Exploitation",
        f"{len(lambdas)} Lambda, {len(users)} IAM users",
    ])

    table = format_table(
        "Attack Summary",
        ["Phase", "Name", "Result"],
        rows,
        ["bright_cyan", "bright_white", "bright_green"],
    )
    console.print(table)


# =============================================================================
# Manual Mode
# =============================================================================


def run_manual(config: AttackConfig) -> None:
    """Print configuration and commands for manual execution."""
    console.print(
        Panel(
            "[bold bright_yellow]MANUAL MODE[/bold bright_yellow]\n"
            "[dim]Infrastructure is deployed. Follow the commands below "
            "or see docs/attack_guide.md for the full walkthrough.[/dim]",
            border_style="bright_yellow",
            box=box.DOUBLE,
        )
    )

    config.print_config_summary()

    console.print()
    console.print("[bold]Quick Start Commands:[/bold]")
    console.print()
    pn = config.codebuild_project_name
    console.print("  [bright_cyan]# Step 1: Discover CodeBuild config[/bright_cyan]")
    console.print(f"  aws codebuild batch-get-projects --names \"{pn}\"")
    console.print()
    console.print("  [bright_cyan]# Step 2: Analyze webhook filters[/bright_cyan]")
    console.print(
        f"  aws codebuild batch-get-projects --names \"{pn}\" "
        "--query 'projects[0].webhook.filterGroups'"
    )
    console.print()
    console.print("  [bright_cyan]# Step 3: Extract secrets[/bright_cyan]")
    console.print(
        f"  aws secretsmanager get-secret-value "
        f"--secret-id \"{config.github_automation_secret_name}\""
    )
    console.print()
    console.print("[dim]Full walkthrough: docs/attack_guide.md[/dim]")


# =============================================================================
# Main Entry Point
# =============================================================================


def main() -> None:
    parser = argparse.ArgumentParser(
        description="CodeBreach: CI/CD Supply Chain Attack Simulation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Commands:\n"
            "  status          Show lab environment status\n"
            "  report [LOG]    Generate report from last log file\n"
            "\n"
            "Examples:\n"
            "  python main.py                  # Interactive menu\n"
            "  python main.py --auto           # Full automated attack\n"
            "  python main.py --auto --log     # Attack with logging\n"
            "  python main.py status           # Check lab state\n"
        ),
    )
    parser.add_argument(
        "command", nargs="?", default=None, help="Subcommand: status, report"
    )
    parser.add_argument(
        "--auto", action="store_true", help="Run all phases automatically"
    )
    parser.add_argument(
        "--manual",
        action="store_true",
        help="Print manual execution commands",
    )
    parser.add_argument(
        "--log",
        action="store_true",
        help="Write structured log to logs/ directory",
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="Generate Markdown report after attack",
    )

    args = parser.parse_args()

    # --- Handle subcommands that don't need infra ---

    if args.command == "status":
        import status as status_mod

        console.print(BANNER)
        status_mod.run_status()
        return

    if args.command == "report":
        import report as report_mod

        log_dir = Path(__file__).resolve().parent.parent / "logs"
        logs = (
            sorted(log_dir.glob("*.jsonl"), reverse=True)
            if log_dir.exists()
            else []
        )
        if not logs:
            print_error("No log files found. Run an attack with --log first.")
            sys.exit(1)
        log_path = str(logs[0])
        print_info(f"Generating report from: {log_path}")
        report_path = report_mod.generate_report_from_log(log_path)
        if report_path:
            print_success(f"Report written to: {report_path}")
        return

    # --- Main attack flow ---

    console.print(BANNER)

    # Init logging if requested
    log_path = None
    if args.log or args.report:
        log_path = init_logging()
        print_success(f"Logging to: {log_path}")

    # Clear progress from previous runs
    import os

    progress_file = str(
        Path(__file__).resolve().parent.parent
        / "logs"
        / ".attack-progress.json"
    )
    if os.path.exists(progress_file):
        os.remove(progress_file)

    # Check infrastructure is deployed
    if not terraform_is_deployed():
        print_error("Infrastructure not deployed. Run ./setup.sh first.")
        sys.exit(1)

    # Load configuration
    try:
        config = AttackConfig(terraform_dir=TERRAFORM_DIR)
    except (RuntimeError, SystemExit) as exc:
        print_error(
            f"Failed to load config: {exc}. "
            "Is infrastructure deployed? Run ./setup.sh"
        )
        sys.exit(1)

    # Route to mode
    all_results = {}
    try:
        if args.manual:
            run_manual(config)
        elif args.auto:
            all_results = run_all_phases(config)
        else:
            all_results = run_interactive(config)
    except KeyboardInterrupt:
        console.print("\n\n  [dim]Attack interrupted by user.[/dim]")
    except Exception as exc:
        print_error(f"Unexpected error: {exc}")
        raise
    finally:
        close_logging()

    # Generate report if requested
    if args.report and all_results:
        import report as report_mod

        report_path = report_mod.generate_report(
            all_results, config=config, log_file=log_path
        )
        print_success(f"Report written to: {report_path}")

    # Cleanup reminder
    if not args.manual:
        console.print()
        print_warning(
            "Remember to clean up! Run: ./cleanup.sh "
            "or: cd terraform && terraform destroy"
        )


if __name__ == "__main__":
    main()
