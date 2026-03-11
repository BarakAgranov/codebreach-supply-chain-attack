#!/bin/bash
# =============================================================================
# cleanup.sh -- Complete Cleanup for "CodeBreach"
# =============================================================================
# Removes all resources created during the attack and the lab.
# Handles resources not managed by Terraform FIRST, then runs terraform
# destroy, optionally deletes the GitHub repo, and cleans up local artifacts.
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
# Extract GitHub credentials from terraform.tfvars (if available)
# =============================================================================

GH_TOKEN=""
GH_OWNER=""
GH_REPO=""

if [ -f "${TERRAFORM_DIR}/terraform.tfvars" ]; then
    GH_TOKEN=$(grep 'github_token' "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null | sed 's/.*= *"//' | sed 's/".*//')
    GH_OWNER=$(grep 'github_owner' "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null | sed 's/.*= *"//' | sed 's/".*//')
    GH_REPO=$(grep 'github_repo' "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null | sed 's/.*= *"//' | sed 's/".*//')
    GH_REPO="${GH_REPO:-mega-sdk-js}"
fi

# =============================================================================
# [1/6] DELETE NON-TERRAFORM RESOURCES
# =============================================================================

echo -e "${CYAN}[1/6] Deleting resources not managed by Terraform...${NC}"

# --- Delete CloudWatch Log Groups created by CodeBuild/Lambda ---
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

# =============================================================================
# [2/6] TERRAFORM DESTROY
# =============================================================================

TF_DESTROY_SUCCESS=false

echo -e "\n${CYAN}[2/6] Running terraform destroy...${NC}"
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
# [3/6] DELETE GITHUB REPOSITORY
# =============================================================================

echo -e "\n${CYAN}[3/6] GitHub cleanup...${NC}"

if [ -n "${GH_TOKEN}" ] && [ -n "${GH_OWNER}" ] && [ -n "${GH_REPO}" ]; then
    # Check if the repo exists
    REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GH_TOKEN}" \
        "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}" 2>/dev/null)

    if [ "${REPO_CHECK}" = "200" ]; then
        echo -e "  Found repository: ${GH_OWNER}/${GH_REPO}"
        read -p "  Delete the GitHub repository? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            DELETE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X DELETE \
                -H "Authorization: token ${GH_TOKEN}" \
                "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}" 2>/dev/null)
            if [ "${DELETE_CODE}" = "204" ]; then
                echo -e "  ${GREEN}Deleted repository: ${GH_OWNER}/${GH_REPO}${NC}"
            else
                echo -e "  ${YELLOW}Could not delete repository (HTTP ${DELETE_CODE}).${NC}"
                echo -e "  ${YELLOW}  Your PAT may be missing the 'delete_repo' scope.${NC}"
                echo -e "  ${YELLOW}  Delete manually: https://github.com/${GH_OWNER}/${GH_REPO}/settings${NC}"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo -e "  ${YELLOW}Skipped. Delete manually if no longer needed:${NC}"
            echo -e "  ${YELLOW}  https://github.com/${GH_OWNER}/${GH_REPO}/settings${NC}"
        fi
    else
        echo -e "  ${YELLOW}Repository ${GH_OWNER}/${GH_REPO} not found (already deleted or token expired)${NC}"
    fi
else
    echo -e "  ${YELLOW}No GitHub credentials found in terraform.tfvars. Skipping.${NC}"
    echo -e "  ${YELLOW}If you created a repo, delete it manually on GitHub.${NC}"
fi

# =============================================================================
# [4/6] CLEAN UP LOCAL ARTIFACTS
# =============================================================================

echo -e "\n${CYAN}[4/6] Cleaning up local artifacts...${NC}"

rm -f "${SCRIPT_DIR}/logs/.attack-progress.json" 2>/dev/null || true
rm -rf "${TERRAFORM_DIR}/.terraform" 2>/dev/null && echo -e "  ${GREEN}Removed .terraform/${NC}" || true

# Only delete state files if terraform destroy succeeded
if [ "${TF_DESTROY_SUCCESS}" = true ]; then
    rm -f "${TERRAFORM_DIR}/terraform.tfstate" 2>/dev/null && echo -e "  ${GREEN}Removed terraform.tfstate${NC}" || true
    rm -f "${TERRAFORM_DIR}/terraform.tfstate.backup" 2>/dev/null && echo -e "  ${GREEN}Removed terraform.tfstate.backup${NC}" || true
    rm -f "${TERRAFORM_DIR}/terraform.tfvars" 2>/dev/null && echo -e "  ${GREEN}Removed terraform.tfvars${NC}" || true
else
    echo -e "  ${YELLOW}Keeping terraform.tfstate and terraform.tfvars (destroy had errors)${NC}"
fi

rm -f "${TERRAFORM_DIR}/.terraform.lock.hcl" 2>/dev/null && echo -e "  ${GREEN}Removed .terraform.lock.hcl${NC}" || true
rm -f "${TERRAFORM_DIR}/lambda_function.zip" 2>/dev/null && echo -e "  ${GREEN}Removed lambda zip${NC}" || true
find "${SCRIPT_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -f /tmp/codebuild_project.json /tmp/lambda_response.json /tmp/lambda_output.json 2>/dev/null || true
echo -e "  ${GREEN}Local artifacts cleaned${NC}"

# =============================================================================
# [5/6] CLEAN UP AWS CLI PROFILES
# =============================================================================

echo -e "\n${CYAN}[5/6] Cleaning up AWS CLI attacker profiles...${NC}"
for PROFILE in attacker attacker-admin; do
    aws configure set aws_access_key_id "" --profile "${PROFILE}" 2>/dev/null || true
    aws configure set aws_secret_access_key "" --profile "${PROFILE}" 2>/dev/null || true
done
echo -e "  ${GREEN}CLI profiles cleared${NC}"

# Unset any lingering environment variables
unset STOLEN_PAT GITHUB_TOKEN NPM_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# =============================================================================
# [6/6] VERIFICATION CHECKLIST
# =============================================================================

echo -e "\n${CYAN}[6/6] Verification checklist${NC}"
echo -e "${YELLOW}"
echo "  Verify in the AWS Console:"
echo ""
echo "  [ ] CodeBuild > Projects: No codebreach-lab-* projects"
echo "  [ ] Secrets Manager: No codebreach-lab/* secrets"
echo "  [ ] S3 > Buckets: No codebreach-lab-* buckets"
echo "  [ ] Lambda > Functions: No codebreach-lab-* functions"
echo "  [ ] CloudTrail: No codebreach-lab-trail"
echo "  [ ] IAM > Roles: No codebreach-lab-* roles"
echo "  [ ] CloudWatch Logs: No /aws/codebuild/codebreach-lab-* log groups"
echo ""
echo "  Verify on GitHub:"
echo ""
echo "  [ ] Repository deleted (or delete at Settings > Danger Zone)"
echo "  [ ] Revoke lab PAT at: https://github.com/settings/tokens"
echo "      (This cannot be automated -- you must do it in the browser)"
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