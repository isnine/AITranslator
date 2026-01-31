#!/bin/bash
#
# ci_post_clone.sh
# Xcode Cloud post-clone script for AITranslator
#
# This script is automatically executed by Xcode Cloud after cloning the repository.
# It injects secrets from Xcode Cloud environment variables into the build configuration.
#
# Required Environment Variables in Xcode Cloud:
#   AITRANSLATOR_CLOUD_SECRET - HMAC signing secret (mark as Secret)
#
# Optional Environment Variables:
#   AITRANSLATOR_CLOUD_TOKEN      - Authentication token (mark as Secret)
#   AITRANSLATOR_CLOUD_ENDPOINT   - Custom endpoint URL
#   AITRANSLATOR_BUILD_ENVIRONMENT - Override build environment

set -e

echo "================================================"
echo "  Xcode Cloud Post-Clone Script"
echo "  AITranslator"
echo "================================================"
echo ""

# Navigate to repository root
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Repository: $CI_PRIMARY_REPOSITORY_PATH"
echo "Workflow:   $CI_WORKFLOW"
echo "Branch:     $CI_BRANCH"
echo "Commit:     $CI_COMMIT"
echo ""

# Set build environment to 'appstore' for Xcode Cloud builds
export AITRANSLATOR_BUILD_ENVIRONMENT="${AITRANSLATOR_BUILD_ENVIRONMENT:-appstore}"

# Call the unified secrets injection script
echo "Running secrets injection..."
./Scripts/inject-secrets.sh

echo ""
echo "================================================"
echo "  Post-Clone Complete"
echo "================================================"
