#!/bin/bash
set -e
set -o pipefail

# End-to-end test script for the One-off Fargate Task
# Usage:
#   ./scripts/run-e2e.sh          # Runs all steps including cleanup
#   ./scripts/run-e2e.sh --no-cleanup # Runs all steps EXCEPT cleanup

# --- Configuration & Flags ---
PERFORM_CLEANUP=true
if [[ "$1" == "--no-cleanup" ]]; then
  PERFORM_CLEANUP=false
  echo "INFO: Cleanup step will be skipped."
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
SHARED_INFRA_DIR=$(realpath "$PROJECT_ROOT/../../infra/terraform")
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"
TEST_RUNNER_DIR="$PROJECT_ROOT/tests/taskrun"

# --- Helper Functions ---
log() {
  echo "[E2E] INFO: $1"
}

error() {
  echo "[E2E] ERROR: $1" >&2
  exit 1
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    error "Command '$1' not found. Please install it and ensure it's in your PATH."
  fi
}

# --- Sanity Checks ---
log "Running sanity checks..."
check_command docker
check_command go
check_command terraform
check_command jq
check_command aws

log "Checking for required environment variables..."
required_env_vars=("AWS_ACCOUNT_ID" "AWS_REGION" "TF_VPC_ID")
missing_env_vars=()
for var in "${required_env_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_env_vars+=("$var")
    fi
done
if [[ ${#missing_env_vars[@]} -ne 0 ]]; then
    echo "ERROR: Missing required environment variables:" >&2
    for var in "${missing_env_vars[@]}"; do
        echo "  - $var" >&2
    done
    error "Please set them (e.g., in .env.local) and ensure they are loaded into your environment."
fi
log "Environment checks passed."

# --- Step 0: Check Shared Infrastructure ---
log "Step 0: Checking shared infrastructure..."
if [[ ! -f "$SHARED_INFRA_DIR/terraform.tfstate" ]]; then
    log "Shared infrastructure not deployed. Deploying now..."
    cd "$SHARED_INFRA_DIR"
    terraform init -input=false || error "Shared infra Terraform init failed."
    terraform apply -auto-approve -input=false || error "Shared infra Terraform apply failed."
fi

log "Fetching shared infrastructure outputs..."
cd "$SHARED_INFRA_DIR"
ECS_CLUSTER_ARN=$(terraform output -raw ecs_cluster_arn)
if [[ -z "$ECS_CLUSTER_ARN" ]]; then
    error "Failed to fetch ecs_cluster_arn from shared infrastructure."
fi
log "ECS Cluster ARN: $ECS_CLUSTER_ARN"
export TF_ECS_CLUSTER_ARN="$ECS_CLUSTER_ARN"

# --- Step 1: Deploy Infrastructure using apply.sh ---
log "Step 1: Deploying infrastructure using apply.sh..."
cd "$SCRIPT_DIR"
chmod +x apply.sh
./apply.sh || error "apply.sh failed."

# --- Step 2: Fetch outputs and run test ---
log "Step 2: Running test..."
cd "$TF_APP_DIR"
TASK_DEFINITION_ARN=$(terraform output -raw task_definition_arn)
SECURITY_GROUP_ID=$(terraform output -raw security_group_id)
CONTAINER_NAME=$(terraform output -raw container_name)
SUBNET_IDS=$(terraform output -json subnet_ids | jq -r 'join(",")')
log "Task Definition ARN: $TASK_DEFINITION_ARN"
log "Subnet IDs: $SUBNET_IDS"

cd "$TEST_RUNNER_DIR"
log "Building test-runner Go application..."
go mod tidy || log "Warning: go mod tidy failed, continuing anyway"
go build -o test-runner . || error "Failed to build test-runner."

log "Executing test-runner..."
./test-runner \
    --cluster-arn="$ECS_CLUSTER_ARN" \
    --task-definition-arn="$TASK_DEFINITION_ARN" \
    --subnet-ids="$SUBNET_IDS" \
    --security-group-id="$SECURITY_GROUP_ID" \
    --container-name="$CONTAINER_NAME" \
    --input='{"message": "Hello from E2E test!", "data": {"test": true}}' \
    || error "Test runner failed."

log "Test completed successfully!"

# --- Step 3: Cleanup using destroy.sh ---
if [[ "$PERFORM_CLEANUP" == true ]]; then
  log "Step 3: Cleaning up infrastructure using destroy.sh..."
  cd "$SCRIPT_DIR"
  chmod +x destroy.sh
  ./destroy.sh || error "destroy.sh failed."
  log "Infrastructure cleaned up successfully."
  log "Note: Shared infrastructure (infra/terraform) was NOT destroyed."
else
  log "Step 3: Skipping cleanup as requested."
fi

log "E2E script completed successfully!"
exit 0
