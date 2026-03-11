"""
config.py -- Configuration bridge between Terraform outputs and attack scripts.

Reads Terraform outputs to get infrastructure details (project names, secret
ARNs, bucket names, etc.) and manages credentials used during the attack.

Two credential types:
  1. AWS admin session: Used for all AWS operations (simulating both the
     public project visibility and the build environment's role access).
  2. Stolen GitHub PAT: Extracted from Secrets Manager during Phase 3,
     used for GitHub API calls in Phases 4+.
"""
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

import boto3

from utils import print_error, print_info, print_success, print_warning


class AttackConfig:
    """
    Manages configuration, credentials, and sessions for the attack.

    Reads Terraform outputs to discover infrastructure details and provides
    accessor properties for each value the attack scripts need.
    """

    def __init__(self, terraform_dir: Optional[str] = None) -> None:
        """
        Initialize the config by reading Terraform outputs.

        Args:
            terraform_dir: Path to the terraform/ directory. Defaults to
                           ../terraform relative to this script.
        """
        if terraform_dir is None:
            terraform_dir = str(
                Path(__file__).resolve().parent.parent / "terraform"
            )
        self.terraform_dir = terraform_dir
        self._tf_outputs: Dict[str, Any] = {}
        self._aws_session: Optional[boto3.Session] = None
        self._stolen_github_pat: Optional[str] = None
        self._stolen_npm_token: Optional[str] = None
        self._load_terraform_outputs()

    # =========================================================================
    # Terraform Output Loading
    # =========================================================================

    def _load_terraform_outputs(self) -> None:
        """
        Read Terraform outputs via subprocess and parse the JSON result.

        Runs `terraform output -json` in the terraform directory and stores
        the parsed output values for use by accessor properties.
        """
        try:
            result = subprocess.run(
                ["terraform", "output", "-json"],
                cwd=self.terraform_dir,
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                print_error(
                    f"Terraform output failed: {result.stderr.strip()}"
                )
                print_info(
                    "Make sure you have run 'terraform apply' in the "
                    "terraform/ directory first."
                )
                raise RuntimeError("Terraform outputs not available")

            raw = json.loads(result.stdout)
            # Terraform output -json wraps each value in {"value": ..., "type": ...}
            self._tf_outputs = {k: v.get("value") for k, v in raw.items()}
        except FileNotFoundError:
            raise RuntimeError(
                "Terraform CLI not found. Install Terraform >= 1.11.0."
            )
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Failed to parse Terraform output: {exc}")
        except subprocess.TimeoutExpired:
            raise RuntimeError(
                "Terraform output timed out after 30 seconds."
            )

    # =========================================================================
    # Infrastructure Properties (from Terraform outputs)
    # =========================================================================

    @property
    def aws_region(self) -> str:
        """AWS region where infrastructure is deployed."""
        return self._tf_outputs.get("aws_region", "us-east-1")

    @property
    def codebuild_project_name(self) -> str:
        """Name of the CodeBuild project."""
        return self._tf_outputs.get("codebuild_project_name", "")

    @property
    def codebuild_project_arn(self) -> str:
        """ARN of the CodeBuild project."""
        return self._tf_outputs.get("codebuild_project_arn", "")

    @property
    def codebuild_role_arn(self) -> str:
        """ARN of the CodeBuild IAM role."""
        return self._tf_outputs.get("codebuild_role_arn", "")

    @property
    def vulnerable_filter_pattern(self) -> str:
        """The unanchored ACTOR_ACCOUNT_ID filter pattern."""
        return self._tf_outputs.get("vulnerable_filter_pattern", "")

    @property
    def secure_filter_pattern(self) -> str:
        """What the filter should look like (with anchors)."""
        return self._tf_outputs.get("secure_filter_pattern", "")

    @property
    def artifacts_bucket(self) -> str:
        """S3 bucket for build artifacts."""
        return self._tf_outputs.get("artifacts_bucket", "")

    @property
    def github_automation_secret_name(self) -> str:
        """Secrets Manager name for the GitHub PAT."""
        return self._tf_outputs.get("github_automation_secret_name", "")

    @property
    def npm_token_secret_name(self) -> str:
        """Secrets Manager name for the npm token."""
        return self._tf_outputs.get("npm_token_secret_name", "")

    @property
    def database_secret_name(self) -> str:
        """Secrets Manager name for the database credentials."""
        return self._tf_outputs.get("database_secret_name", "")

    @property
    def secrets_manager_names(self) -> list:
        """List of all Secrets Manager secret names."""
        return self._tf_outputs.get("secrets_manager_names", [])

    @property
    def lambda_function_name(self) -> str:
        """Name of the simulated deployment Lambda function."""
        return self._tf_outputs.get("lambda_function_name", "")

    @property
    def cloudtrail_name(self) -> str:
        """Name of the CloudTrail trail."""
        return self._tf_outputs.get("cloudtrail_name", "")

    @property
    def github_owner(self) -> str:
        """GitHub username or organization."""
        return self._tf_outputs.get("github_owner", "")

    @property
    def github_repo(self) -> str:
        """GitHub repository name."""
        return self._tf_outputs.get("github_repo", "")

    @property
    def github_repo_url(self) -> str:
        """Full GitHub repository URL."""
        return self._tf_outputs.get("github_repo_url", "")

    @property
    def project_prefix(self) -> str:
        """Project prefix used for resource naming."""
        return self._tf_outputs.get("project_prefix", "codebreach-lab")

    # =========================================================================
    # AWS Session
    # =========================================================================

    @property
    def aws_session(self) -> boto3.Session:
        """
        boto3 session using the default AWS credentials.

        For this scenario, we use admin credentials throughout (simulating
        both public project visibility and CodeBuild role access).
        """
        if self._aws_session is None:
            self._aws_session = boto3.Session(
                region_name=self.aws_region
            )
        return self._aws_session

    # =========================================================================
    # Stolen GitHub PAT (set during Phase 3)
    # =========================================================================

    def set_stolen_github_pat(self, pat: str) -> None:
        """Store the GitHub PAT stolen from Secrets Manager."""
        self._stolen_github_pat = pat

    @property
    def stolen_github_pat(self) -> Optional[str]:
        """The stolen GitHub PAT, or None if not yet extracted."""
        return self._stolen_github_pat

    def require_github_pat(self) -> str:
        """
        Return the stolen GitHub PAT, or raise if it has not been extracted.

        Raises RuntimeError instead of sys.exit so interactive mode
        can catch it and return to the menu.
        """
        if self._stolen_github_pat is None:
            raise RuntimeError(
                "GitHub PAT not available. "
                "Run Phase 3 (Credential Theft) first."
            )
        return self._stolen_github_pat

    def set_stolen_npm_token(self, token: str) -> None:
        """Store the npm token stolen from Secrets Manager."""
        self._stolen_npm_token = token

    @property
    def stolen_npm_token(self) -> Optional[str]:
        """The stolen npm token, or None if not yet extracted."""
        return self._stolen_npm_token

    # =========================================================================
    # Utility
    # =========================================================================

    def get_account_id(self) -> str:
        """Get the AWS account ID from the current session."""
        sts = self.aws_session.client("sts")
        return sts.get_caller_identity()["Account"]

    def print_config_summary(self) -> None:
        """Print a summary of the current configuration."""
        from rich.table import Table
        from rich import box

        table = Table(
            title="Attack Configuration",
            box=box.ROUNDED,
            show_lines=False,
        )
        table.add_column("Parameter", style="bright_cyan")
        table.add_column("Value", style="white")

        table.add_row("CodeBuild Project", self.codebuild_project_name)
        table.add_row("GitHub Repository", self.github_repo_url)
        table.add_row("Artifacts Bucket", self.artifacts_bucket)
        table.add_row("Lambda Function", self.lambda_function_name)
        table.add_row("Region", self.aws_region)
        table.add_row(
            "Vulnerable Filter", self.vulnerable_filter_pattern
        )
        table.add_row("Secure Filter", self.secure_filter_pattern)
        table.add_row(
            "Stolen GitHub PAT",
            f"{self._stolen_github_pat[:15]}..."
            if self._stolen_github_pat
            else "Not yet stolen",
        )

        from utils import console

        console.print(table)
