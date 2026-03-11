#!/bin/bash
# =============================================================================
# cleanup.sh -- Complete Cleanup for "CodeBreach"
# =============================================================================
# Removes all resources created during the attack and the lab.
# Handles resources not managed by Terraform FIRST, then runs terraform
# destroy, and finally cleans up local artifacts.
#
# IMPORTANT: No set -e. Cleanup is best-effort -- if one step fails,
# we continue with the rest. A half-cleanup is worse than a full attempt.
#
# Usage: ./cleanup.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

ERRORS=0

echo -e "${CYAN}"
echo "============================================="
echo "  CodeBreach -- Cleanup"
echo "============================================="
echo -e "${NC}"

# =============================================================================
# [1/5] DELETE NON-TERRAFORM RESOURCES
# =============================================================================

echo -e "${CYAN}[1/5] Deleting resources not managed by Terraform...${NC}"

# --- Delete CloudWatch Log Groups created by CodeBuild/Lambda ---
# These are auto-created by AWS when builds run or Lambda executes,
# and Terraform does not manage their lifecycle.
for LOG_GROUP in \
    "/aws/codebuild/codebreach-lab-sdk-build" \
    "/aws/lambda/codebreach-lab-deploy-function"; do
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP}"; then
        if aws logs delete-log-group --log-group-name "${LOG_GROUP}" 2>/dev/null; then
            echo -e "  ${GREEN}Deleted log group: ${LOG_GROUP}${NC}"
        else
            echo -e "  ${YELLOW}Could not delete log group: ${LOG_GROUP}${NC}"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo -e "  ${YELLOW}Log group not found: ${LOG_GROUP} (already cleaned or never created)${NC}"
    fi
done

# --- Delete attacker branch from GitHub (if it was pushed manually) ---
# This only applies if the user followed the manual attack guide and
# pushed the attacker/innocent-bugfix branch to GitHub.
echo -e "  Checking for attacker branch on GitHub..."
echo -e "  ${YELLOW}If you pushed a branch to GitHub, delete it manually:${NC}"
echo -e "  ${YELLOW}  git push origin --delete attacker/innocent-bugfix${NC}"

# =============================================================================
# [2/5] TERRAFORM DESTROY
# =============================================================================

TF_DESTROY_SUCCESS=false

echo -e "\n${CYAN}[2/5] Running terraform destroy...${NC}"
if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    cd "${TERRAFORM_DIR}"
    if terraform destroy -auto-approve -input=false; then
        echo -e "  ${GREEN}Terraform resources destroyed${NC}"
        TF_DESTROY_SUCCESS=true
    else
        echo -e "  ${RED}terraform destroy failed (see errors above)${NC}"
        echo -e "  ${YELLOW}Some resources may still exist. Check the AWS Console.${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${YELLOW}No terraform.tfstate found. Skipping terraform destroy.${NC}"
    TF_DESTROY_SUCCESS=true
fi

# =============================================================================
# [3/5] CLEAN UP LOCAL ARTIFACTS
# =============================================================================

echo -e "\n${CYAN}[3/5] Cleaning up local artifacts...${NC}"

rm -f "${SCRIPT_DIR}/logs/.attack-progress.json" 2>/dev/null || true
rm -rf "${TERRAFORM_DIR}/.terraform" 2>/dev/null && echo -e "  ${GREEN}Removed .terraform/${NC}" || true

# Only delete state files if terraform destroy succeeded
if [ "${TF_DESTROY_SUCCESS}" = true ]; then
    rm -f "${TERRAFORM_DIR}/terraform.tfstate" 2>/dev/null && echo -e "  ${GREEN}Removed terraform.tfstate${NC}" || true
    rm -f "${TERRAFORM_DIR}/terraform.tfstate.backup" 2>/dev/null && echo -e "  ${GREEN}Removed terraform.tfstate.backup${NC}" || true
else
    echo -e "  ${YELLOW}Keeping terraform.tfstate (destroy had errors -- you may need to re-run)${NC}"
fi

rm -f "${TERRAFORM_DIR}/.terraform.lock.hcl" 2>/dev/null && echo -e "  ${GREEN}Removed .terraform.lock.hcl${NC}" || true
rm -f "${TERRAFORM_DIR}/lambda_function.zip" 2>/dev/null && echo -e "  ${GREEN}Removed lambda zip${NC}" || true
find "${SCRIPT_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -f /tmp/codebuild_project.json /tmp/lambda_response.json /tmp/lambda_output.json 2>/dev/null || true
echo -e "  ${GREEN}Local artifacts cleaned${NC}"

# =============================================================================
# [4/5] CLEAN UP AWS CLI PROFILES
# =============================================================================

echo -e "\n${CYAN}[4/5] Cleaning up AWS CLI attacker profiles...${NC}"
for PROFILE in attacker attacker-admin; do
    aws configure set aws_access_key_id "" --profile "${PROFILE}" 2>/dev/null || true
    aws configure set aws_secret_access_key "" --profile "${PROFILE}" 2>/dev/null || true
done
echo -e "  ${GREEN}CLI profiles cleared${NC}"

# Unset any lingering environment variables
unset STOLEN_PAT GITHUB_TOKEN NPM_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# =============================================================================
# [5/5] VERIFICATION CHECKLIST
# =============================================================================

echo -e "\n${CYAN}[5/5] Verification checklist${NC}"
echo -e "${YELLOW}"
echo "  Log into the AWS Console and verify:"
echo ""
echo "  [ ] CodeBuild > Projects: No codebreach-lab-* projects"
echo "  [ ] Secrets Manager: No codebreach-lab/* secrets"
echo "  [ ] S3 > Buckets: No codebreach-lab-* buckets"
echo "  [ ] Lambda > Functions: No codebreach-lab-* functions"
echo "  [ ] CloudTrail: No codebreach-lab-trail"
echo "  [ ] IAM > Roles: No codebreach-lab-* roles"
echo "  [ ] CloudWatch Logs: No /aws/codebuild/codebreach-lab-* log groups"
echo ""
echo "  Also verify on GitHub:"
echo "  [ ] Delete the mega-sdk-js repository (if no longer needed)"
echo "  [ ] Revoke the codebreach-lab PAT at https://github.com/settings/tokens"
echo -e "${NC}"

if [ ${ERRORS} -gt 0 ]; then
    echo -e "${YELLOW}=============================================${NC}"
    echo -e "${YELLOW}  Cleanup finished with ${ERRORS} warning(s).${NC}"
    echo -e "${YELLOW}  Check the output above and verify manually.${NC}"
    echo -e "${YELLOW}=============================================${NC}"
else
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Cleanup Complete!${NC}"
    echo -e "${GREEN}=============================================${NC}"
fi
