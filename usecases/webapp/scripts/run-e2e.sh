#!/bin/bash
set -e

# End-to-end test script for webapp use case (ALB authenticate-cognito)
# This script deploys infrastructure, runs the test, and optionally cleans up

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"
TEST_DIR="$PROJECT_ROOT/tests/webtest"
SHARED_INFRA_DIR=$(realpath "$PROJECT_ROOT/../../infra/terraform")

# Parse arguments
CLEANUP=true
for arg in "$@"; do
    case $arg in
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
    esac
done

cleanup() {
    if [ "$CLEANUP" = true ]; then
        echo "[E2E] INFO: Cleaning up infrastructure..."
        cd "$SCRIPT_DIR"
        ./destroy.sh || true
    else
        echo "[E2E] INFO: Skipping cleanup (--no-cleanup specified)"
    fi
}

trap cleanup EXIT

echo "[E2E] INFO: Running sanity checks..."

# Check required environment variables
echo "[E2E] INFO: Checking for required environment variables..."
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "ap-northeast-1")
fi
if [ -z "$AWS_ACCOUNT_ID" ]; then
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
fi

echo "[E2E] INFO: AWS Region: $AWS_REGION"
echo "[E2E] INFO: AWS Account: $AWS_ACCOUNT_ID"
echo "[E2E] INFO: Environment checks passed."

# Step 1: Deploy infrastructure
echo "[E2E] INFO: Step 1: Deploying infrastructure using apply.sh..."
cd "$SCRIPT_DIR"
chmod +x apply.sh build.sh set-tf-vars.sh destroy.sh
./apply.sh

# Get outputs for test
echo "[E2E] INFO: Step 2: Getting infrastructure outputs..."
eval $(./set-tf-vars.sh)

ALB_URL=$(terraform -chdir="$TF_APP_DIR" output -raw alb_url 2>/dev/null)
COGNITO_DOMAIN=$(terraform -chdir="$TF_APP_DIR" output -raw cognito_domain 2>/dev/null)
CLIENT_ID=$(terraform -chdir="$TF_APP_DIR" output -raw cognito_client_id 2>/dev/null)
TEST_USER_EMAIL=$(terraform -chdir="$TF_APP_DIR" output -raw test_user_email 2>/dev/null)
TEST_USER_PASSWORD=$(terraform -chdir="$TF_APP_DIR" output -raw test_user_password 2>/dev/null)

echo "[E2E] INFO: ALB URL: $ALB_URL"
echo "[E2E] INFO: Cognito Domain: $COGNITO_DOMAIN"
echo "[E2E] INFO: Client ID: $CLIENT_ID"
echo "[E2E] INFO: Test User: $TEST_USER_EMAIL"

# Step 3: Build and run test
echo "[E2E] INFO: Step 3: Building test runner..."
cd "$TEST_DIR"
go mod tidy
go build -o webtest .

echo "[E2E] INFO: Step 4: Running webapp authentication test..."
./webtest \
    -alb-url="$ALB_URL" \
    -cognito-domain="$COGNITO_DOMAIN" \
    -region="$AWS_REGION" \
    -client-id="$CLIENT_ID" \
    -username="$TEST_USER_EMAIL" \
    -password="$TEST_USER_PASSWORD" \
    -timeout=5m

TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "[E2E] INFO: Test completed successfully!"
else
    echo "[E2E] ERROR: Test failed with exit code $TEST_EXIT_CODE"
    exit $TEST_EXIT_CODE
fi
