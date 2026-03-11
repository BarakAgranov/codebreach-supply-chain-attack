#!/bin/bash
# =============================================================================
# setup.sh -- One-Command Setup for "CodeBreach"
# =============================================================================
# Checks prerequisites, configures the environment, and deploys infrastructure.
# Handles errors gracefully and offers to fix problems automatically.
#
# IMPORTANT: You must create the GitHub repository manually BEFORE running
# this script. See README.md for instructions.
#
# Usage: ./setup.sh
# Safe to re-run: detects partial state and picks up where it left off.
# =============================================================================

# No set -e. Every error is caught explicitly with helpful messages.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
VENV_DIR="${SCRIPT_DIR}/.venv"

echo -e "${CYAN}"
echo "============================================="
echo "  CodeBreach -- Lab Setup"
echo "============================================="
echo -e "${NC}"

# =============================================================================
# [1/7] PRE-FLIGHT CHECKS
# =============================================================================

echo -e "${CYAN}[1/7] Pre-flight checks...${NC}"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}ERROR: Terraform not found. Install Terraform >= 1.11.0${NC}"
    echo "  https://developer.hashicorp.com/terraform/install"
    exit 1
fi
TF_VERSION=$(terraform version 2>/dev/null | head -1 | sed 's/[^0-9.]//g')
echo -e "  Terraform: ${GREEN}${TF_VERSION}${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI not found. Install AWS CLI v2${NC}"
    echo "  https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
fi
AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
echo -e "  AWS CLI: ${GREEN}${AWS_VERSION}${NC}"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: Python 3 not found. Install Python >= 3.10${NC}"
    exit 1
fi
PY_VERSION=$(python3 --version 2>/dev/null | cut -d' ' -f2)
PY_MINOR=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
echo -e "  Python: ${GREEN}${PY_VERSION}${NC}"

# Check git
if ! command -v git &> /dev/null; then
    echo -e "${RED}ERROR: git not found. Install git.${NC}"
    exit 1
fi
GIT_VERSION=$(git --version 2>/dev/null | cut -d' ' -f3)
echo -e "  git: ${GREEN}${GIT_VERSION}${NC}"

# Check jq (optional but recommended)
if command -v jq &> /dev/null; then
    echo -e "  jq: ${GREEN}$(jq --version 2>/dev/null)${NC}"
else
    echo -e "  jq: ${YELLOW}not installed (optional, install with: sudo apt install jq)${NC}"
fi

# =============================================================================
# [2/7] VERIFY AWS CREDENTIALS
# =============================================================================

echo -e "\n${CYAN}[2/7] Verifying AWS credentials...${NC}"

CALLER_IDENTITY=$(aws sts get-caller-identity 2>&1) || true

if echo "${CALLER_IDENTITY}" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    ACCOUNT_ID=$(echo "${CALLER_IDENTITY}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
    IDENTITY_ARN=$(echo "${CALLER_IDENTITY}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
    echo -e "  Account: ${GREEN}${ACCOUNT_ID}${NC}"
    echo -e "  Identity: ${GREEN}${IDENTITY_ARN}${NC}"
    echo -e "${YELLOW}  WARNING: Verify this is a LAB account, not production!${NC}"
else
    echo -e "${RED}ERROR: AWS credentials not configured or invalid${NC}"
    echo -e "${RED}  ${CALLER_IDENTITY}${NC}"
    echo ""
    echo "  Fix: run 'aws configure' or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY"
    exit 1
fi

# =============================================================================
# [3/7] PYTHON VIRTUAL ENVIRONMENT
# =============================================================================

echo -e "\n${CYAN}[3/7] Creating Python virtual environment...${NC}"

# Auto-fix: broken venv from a previous failed run
if [ -d "${VENV_DIR}" ] && [ ! -f "${VENV_DIR}/bin/activate" ]; then
    echo -e "${YELLOW}  Broken .venv detected. Cleaning up and recreating...${NC}"
    rm -rf "${VENV_DIR}"
fi

if [ -d "${VENV_DIR}" ] && [ -f "${VENV_DIR}/bin/activate" ]; then
    echo -e "  Virtual environment already exists and looks healthy"
else
    VENV_OUTPUT=$(python3 -m venv "${VENV_DIR}" 2>&1) || true

    if [ ! -f "${VENV_DIR}/bin/activate" ]; then
        # Check if it is the ensurepip problem
        if echo "${VENV_OUTPUT}" | grep -qi "ensurepip"; then
            echo -e "${YELLOW}  python${PY_MINOR}-venv package is missing.${NC}"
            echo ""
            read -p "  Install it now? (requires sudo) [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if sudo apt install -y "python${PY_MINOR}-venv"; then
                    echo -e "  ${GREEN}Installed python${PY_MINOR}-venv${NC}"
                    rm -rf "${VENV_DIR}"
                    if python3 -m venv "${VENV_DIR}"; then
                        echo -e "  ${GREEN}Created: ${VENV_DIR}${NC}"
                    else
                        echo -e "${RED}ERROR: venv creation still failing${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}ERROR: Failed to install python${PY_MINOR}-venv${NC}"
                    echo "  Try manually: sudo apt install python${PY_MINOR}-venv"
                    exit 1
                fi
            else
                echo -e "${RED}Cannot continue without a virtual environment.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}ERROR: Failed to create virtual environment${NC}"
            echo -e "${RED}  ${VENV_OUTPUT}${NC}"
            exit 1
        fi
    else
        echo -e "  ${GREEN}Created: ${VENV_DIR}${NC}"
    fi
fi

source "${VENV_DIR}/bin/activate"
echo -e "  ${GREEN}Activated virtual environment${NC}"

# =============================================================================
# [4/7] INSTALL PYTHON DEPENDENCIES
# =============================================================================

echo -e "\n${CYAN}[4/7] Installing Python dependencies...${NC}"

pip install --quiet --upgrade pip 2>/dev/null || true

if ! pip install -r "${SCRIPT_DIR}/requirements.txt" 2>&1; then
    echo ""
    echo -e "${RED}ERROR: Failed to install Python dependencies${NC}"
    echo -e "${YELLOW}  Trying fallback: installing without version constraints...${NC}"
    echo ""
    if pip install boto3 rich requests; then
        echo -e "  ${GREEN}Fallback install succeeded${NC}"
    else
        echo -e "${RED}ERROR: Could not install dependencies.${NC}"
        echo "  Check your internet connection and Python version."
        exit 1
    fi
fi
echo -e "  ${GREEN}Dependencies installed${NC}"

# =============================================================================
# [5/7] TERRAFORM CONFIGURATION
# =============================================================================

echo -e "\n${CYAN}[5/7] Configuring Terraform...${NC}"
if [ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]; then
    if [ -f "${TERRAFORM_DIR}/terraform.tfvars.example" ]; then
        cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
        echo -e "  ${GREEN}Copied terraform.tfvars.example to terraform.tfvars${NC}"
        echo ""
        echo -e "${YELLOW}  IMPORTANT: You must edit terraform/terraform.tfvars before continuing!${NC}"
        echo -e "${YELLOW}  Fill in: github_token, github_owner, trusted_github_user_ids${NC}"
        echo ""
        echo -e "  Edit the file:"
        echo -e "    nano ${TERRAFORM_DIR}/terraform.tfvars"
        echo ""
        echo -e "  Then re-run: ./setup.sh"
        exit 0
    else
        echo -e "${RED}ERROR: No terraform.tfvars.example found in ${TERRAFORM_DIR}${NC}"
        exit 1
    fi
else
    # Verify placeholders are replaced
    if grep -q "your_token_here\|your-github-username\|12345678" "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null; then
        echo -e "${YELLOW}  terraform.tfvars still has placeholder values!${NC}"
        echo -e "${YELLOW}  Edit ${TERRAFORM_DIR}/terraform.tfvars with your real values.${NC}"
        echo ""
        echo -e "  Then re-run: ./setup.sh"
        exit 1
    fi
    echo -e "  terraform.tfvars already configured"
fi

# =============================================================================
# [6/7] TERRAFORM INIT
# =============================================================================

echo -e "\n${CYAN}[6/7] Running terraform init...${NC}"
cd "${TERRAFORM_DIR}"

if ! terraform init -input=false; then
    echo ""
    echo -e "${RED}ERROR: terraform init failed${NC}"
    echo ""
    echo "  Common causes:"
    echo "    - No internet (Terraform downloads providers on first init)"
    echo "    - Corrupt state (fix: rm -rf .terraform .terraform.lock.hcl)"
    exit 1
fi
echo -e "  ${GREEN}Terraform initialized${NC}"

# =============================================================================
# [7/7] TERRAFORM APPLY
# =============================================================================

echo -e "\n${CYAN}[7/7] Deploying infrastructure (terraform apply)...${NC}"

if ! terraform apply -auto-approve -input=false; then
    echo ""
    echo -e "${RED}ERROR: terraform apply failed${NC}"
    echo ""
    echo -e "${YELLOW}  Common causes:${NC}"
    echo "    - GitHub PAT does not have repo + admin:repo_hook scopes"
    echo "    - GitHub repository does not exist (create it first!)"
    echo "    - CodeBuild source credential conflict (only one per account)"
    echo "    - Resources from a previous run still exist (run ./cleanup.sh first)"
    echo ""
    echo "  Check the Terraform error output above for details."
    exit 1
fi
echo -e "  ${GREEN}Infrastructure deployed!${NC}"

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

PROJECT_NAME=$(terraform output -raw codebuild_project_name 2>/dev/null || echo "<unknown>")
VULN_FILTER=$(terraform output -raw vulnerable_filter_pattern 2>/dev/null || echo "<unknown>")
REGION=$(terraform output -raw aws_region 2>/dev/null || echo "<unknown>")

echo -e "  CodeBuild Project: ${CYAN}${PROJECT_NAME}${NC}"
echo -e "  Vulnerable Filter: ${CYAN}${VULN_FILTER}${NC}"
echo -e "  Region:            ${CYAN}${REGION}${NC}"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "  ${CYAN}source .venv/bin/activate${NC}"
echo -e "  ${CYAN}cd core${NC}"
echo -e "  ${CYAN}python main.py --auto       ${NC}# Full automated attack"
echo -e "  ${CYAN}python main.py --manual     ${NC}# Manual step-by-step"
echo -e "  ${CYAN}python main.py              ${NC}# Interactive menu"
echo ""
echo -e "  ${YELLOW}When done, clean up with:${NC} ${CYAN}./cleanup.sh${NC}"
