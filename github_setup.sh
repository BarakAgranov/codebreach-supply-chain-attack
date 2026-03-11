#!/bin/bash
# =============================================================================
# github_setup.sh -- Automated GitHub Repository Setup for CodeBreach Lab
# =============================================================================
# Creates the target GitHub repository (mega-sdk-js), populates it with
# the simulated SDK files, and pushes to GitHub.
#
# Usage:
#   ./github_setup.sh <github_username> <github_pat>
#   ./github_setup.sh                    # Prompts interactively
#
# Called automatically by setup.sh when the user chooses automatic setup.
# Can also be run standalone.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_NAME="mega-sdk-js"

# =============================================================================
# Parse arguments or prompt interactively
# =============================================================================

if [ -n "$1" ] && [ -n "$2" ]; then
    GITHUB_USERNAME="$1"
    GITHUB_TOKEN="$2"
else
    echo -e "${CYAN}GitHub Repository Setup${NC}"
    echo ""

    echo -e "  ${CYAN}GitHub username${NC} (e.g. \"octocat\"):"
    read -p "  > " GITHUB_USERNAME
    if [ -z "${GITHUB_USERNAME}" ]; then
        echo -e "${RED}ERROR: Username cannot be empty${NC}"
        exit 1
    fi

    echo ""
    echo -e "  ${CYAN}GitHub PAT (Classic)${NC} -- create one at:"
    echo -e "    ${YELLOW}https://github.com/settings/tokens/new${NC}"
    echo -e "    Required scopes: ${GREEN}repo${NC}, ${GREEN}admin:repo_hook${NC}, ${GREEN}delete_repo${NC}"
    echo -e "    Set expiration to 7 days for lab safety"
    echo ""
    read -s -p "  Paste token (input is hidden): " GITHUB_TOKEN
    echo ""
    if [ -z "${GITHUB_TOKEN}" ]; then
        echo -e "${RED}ERROR: Token cannot be empty${NC}"
        exit 1
    fi
fi

# =============================================================================
# Validate the token
# =============================================================================

echo -e "\n  Validating GitHub credentials..."

AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/user" 2>/dev/null)

HTTP_CODE=$(echo "${AUTH_RESPONSE}" | tail -1)
AUTH_BODY=$(echo "${AUTH_RESPONSE}" | sed '$d')

if [ "${HTTP_CODE}" != "200" ]; then
    echo -e "${RED}ERROR: GitHub authentication failed (HTTP ${HTTP_CODE})${NC}"
    echo -e "${RED}  Check that your token is valid and has not expired.${NC}"
    exit 1
fi

# Verify username matches
API_USERNAME=$(echo "${AUTH_BODY}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))" 2>/dev/null)
if [ "${API_USERNAME}" != "${GITHUB_USERNAME}" ]; then
    echo -e "${YELLOW}  Note: Token belongs to '${API_USERNAME}', not '${GITHUB_USERNAME}'.${NC}"
    echo -e "${YELLOW}  Using '${API_USERNAME}' as the GitHub owner.${NC}"
    GITHUB_USERNAME="${API_USERNAME}"
fi

# Get the numeric user ID
GITHUB_USER_ID=$(echo "${AUTH_BODY}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
echo -e "  ${GREEN}Authenticated as: ${GITHUB_USERNAME} (ID: ${GITHUB_USER_ID})${NC}"

# Check token scopes
SCOPES_HEADER=$(curl -s -I -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/user" 2>/dev/null | grep -i "x-oauth-scopes" | tr -d '\r')
echo -e "  Token scopes: ${SCOPES_HEADER#*: }"

# =============================================================================
# Check if repo already exists
# =============================================================================

echo -e "\n  Checking if repository '${REPO_NAME}' already exists..."

REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_USERNAME}/${REPO_NAME}" 2>/dev/null)

if [ "${REPO_CHECK}" = "200" ]; then
    echo -e "  ${YELLOW}Repository ${GITHUB_USERNAME}/${REPO_NAME} already exists.${NC}"
    echo -e "  ${GREEN}Skipping creation -- will use existing repo.${NC}"
    REPO_EXISTS=true
else
    REPO_EXISTS=false
fi

# =============================================================================
# Create the repository (if it doesn't exist)
# =============================================================================

if [ "${REPO_EXISTS}" = false ]; then
    echo -e "\n  Creating repository: ${GITHUB_USERNAME}/${REPO_NAME}"

    CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/json" \
        -X POST "https://api.github.com/user/repos" \
        -d "{
            \"name\": \"${REPO_NAME}\",
            \"description\": \"CodeBreach attack lab - simulated JavaScript SDK\",
            \"private\": false,
            \"auto_init\": false
        }" 2>/dev/null)

    CREATE_CODE=$(echo "${CREATE_RESPONSE}" | tail -1)
    CREATE_BODY=$(echo "${CREATE_RESPONSE}" | sed '$d')

    if [ "${CREATE_CODE}" != "201" ]; then
        ERROR_MSG=$(echo "${CREATE_BODY}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message','Unknown error'))" 2>/dev/null)
        echo -e "${RED}ERROR: Failed to create repository (HTTP ${CREATE_CODE})${NC}"
        echo -e "${RED}  ${ERROR_MSG}${NC}"
        exit 1
    fi

    echo -e "  ${GREEN}Repository created: https://github.com/${GITHUB_USERNAME}/${REPO_NAME}${NC}"
fi

# =============================================================================
# Generate SDK files in a temp directory
# =============================================================================

WORK_DIR=$(mktemp -d)
echo -e "\n  Generating SDK files in ${WORK_DIR}..."

# --- package.json ---
cat > "${WORK_DIR}/package.json" << 'EOF'
{
  "name": "@megasdk/core",
  "version": "3.42.0",
  "description": "MegaSDK JavaScript Core Library",
  "main": "dist/index.js",
  "scripts": {
    "build": "echo 'Building SDK...' && mkdir -p dist && echo 'module.exports = {};' > dist/index.js",
    "test": "echo 'Running tests...' && echo 'All 42 tests passed'",
    "lint": "echo 'Linting...' && echo 'No issues found'"
  },
  "license": "Apache-2.0"
}
EOF

# --- buildspec.yml ---
# INTENTIONALLY VULNERABLE: This buildspec exposes environment variables
# and runs npm install with scripts enabled (--ignore-scripts=false).
# In the real CodeBreach attack, the malicious npm dependency's preinstall
# script executed during this phase.
cat > "${WORK_DIR}/buildspec.yml" << 'EOF'
version: 0.2

env:
  variables:
    NODE_ENV: "ci"
    SDK_NAME: "mega-sdk-js"
  secrets-manager:
    NPM_TOKEN: "codebreach-lab/npm-publish-token:token"
    GITHUB_TOKEN: "codebreach-lab/github-automation:token"

phases:
  install:
    runtime-versions:
      nodejs: 20
    commands:
      - echo "Installing dependencies..."
      - npm install --ignore-scripts=false
  pre_build:
    commands:
      - echo "Running linter..."
      - npm run lint
  build:
    commands:
      - echo "Building SDK..."
      - npm run build
      - echo "Running tests..."
      - npm run test
  post_build:
    commands:
      - echo "Build complete. Artifacts ready for publishing."

artifacts:
  files:
    - "dist/**/*"
    - "package.json"
EOF

# --- README.md ---
cat > "${WORK_DIR}/README.md" << 'EOF'
# MegaSDK JavaScript Core

The official JavaScript SDK for MegaSDK services.

## Installation

```bash
npm install @megasdk/core
```

## Usage

```javascript
const mega = require('@megasdk/core');
// Your code here
```
EOF

# --- src/index.js ---
mkdir -p "${WORK_DIR}/src"
cat > "${WORK_DIR}/src/index.js" << 'EOF'
/**
 * MegaSDK Core Library
 * This is a simulated SDK for the CodeBreach attack lab.
 */
class MegaSDK {
  constructor(config) {
    this.region = config.region || 'us-east-1';
    this.version = '3.42.0';
  }

  async invoke(action, params) {
    return { status: 'ok', action, params };
  }
}

module.exports = { MegaSDK };
EOF

echo -e "  ${GREEN}Generated: package.json, buildspec.yml, README.md, src/index.js${NC}"

# =============================================================================
# Git init, commit, and push
# =============================================================================

echo -e "\n  Initializing git and pushing to GitHub..."

cd "${WORK_DIR}"
git init -q
git checkout -q -b main
git add -A
git commit -q -m "Initial SDK release v3.42.0"

# Use token-based remote URL (no interactive auth needed)
git remote add origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" 2>/dev/null || \
    git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"

if git push -u origin main -q --force 2>/dev/null; then
    echo -e "  ${GREEN}Pushed to https://github.com/${GITHUB_USERNAME}/${REPO_NAME}${NC}"
else
    echo -e "${RED}ERROR: Git push failed.${NC}"
    echo -e "${RED}  Check that your PAT has the 'repo' scope.${NC}"
    rm -rf "${WORK_DIR}"
    exit 1
fi

# Clean up temp directory
cd - > /dev/null 2>&1
rm -rf "${WORK_DIR}"

# =============================================================================
# Print results (used by setup.sh to extract values)
# =============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  GitHub Setup Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "  Repository:  ${CYAN}https://github.com/${GITHUB_USERNAME}/${REPO_NAME}${NC}"
echo -e "  Owner:       ${CYAN}${GITHUB_USERNAME}${NC}"
echo -e "  User ID:     ${CYAN}${GITHUB_USER_ID}${NC}"
echo ""

# Export values so setup.sh can read them
# (setup.sh sources this script's output via these exports)
export CODEBREACH_GITHUB_USERNAME="${GITHUB_USERNAME}"
export CODEBREACH_GITHUB_TOKEN="${GITHUB_TOKEN}"
export CODEBREACH_GITHUB_USER_ID="${GITHUB_USER_ID}"
export CODEBREACH_GITHUB_REPO="${REPO_NAME}"
