#!/bin/bash
# =============================================================================
# CREDENTIAL EXPOSURE DEMONSTRATION
# =============================================================================
# This script shows what an attacker can access from inside a CodeBuild
# build environment. In the real CodeBreach attack, the attacker embedded
# this as an npm package dependency that ran during "npm install".
#
# The attacker's actual technique was to dump /proc/*/environ to find
# the GitHub PAT in process memory. We simulate this more simply by
# reading environment variables directly.
# =============================================================================

echo "============================================"
echo "  BUILD ENVIRONMENT CREDENTIAL EXPOSURE"
echo "============================================"
echo ""

echo "--- CodeBuild Context ---"
echo "CODEBUILD_BUILD_ID: ${CODEBUILD_BUILD_ID}"
echo "CODEBUILD_SOURCE_REPO_URL: ${CODEBUILD_SOURCE_REPO_URL}"
echo "CODEBUILD_WEBHOOK_ACTOR_ACCOUNT_ID: ${CODEBUILD_WEBHOOK_ACTOR_ACCOUNT_ID}"
echo ""

echo "--- Secret Detection ---"
if [ -n "${GITHUB_TOKEN}" ]; then
    echo "GITHUB_TOKEN present: ${GITHUB_TOKEN:0:10}... (REDACTED)"
    echo "TOKEN LENGTH: ${#GITHUB_TOKEN} characters"
else
    echo "GITHUB_TOKEN: not set in environment"
fi

if [ -n "${NPM_TOKEN}" ]; then
    echo "NPM_TOKEN present: ${NPM_TOKEN:0:10}... (REDACTED)"
else
    echo "NPM_TOKEN: not set in environment"
fi
echo ""

echo "--- Process Memory Scan (simulated) ---"
echo "In the real CodeBreach attack, the attacker ran:"
echo "  cat /proc/*/environ 2>/dev/null | tr '\0' '\n' | grep -i token"
echo ""

echo "--- AWS Credentials (from CodeBuild role) ---"
echo "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
echo "AWS_ACCESS_KEY_ID: present (CodeBuild service role)"
echo ""

echo "============================================"
echo "  DEMONSTRATION COMPLETE"
echo "============================================"
