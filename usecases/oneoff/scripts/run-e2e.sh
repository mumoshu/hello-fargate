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
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"
TEST_RUNNER_DIR="$PROJECT_ROOT/tests/taskrun"
IMAGE_TAG="latest"

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
required_env_vars=("AWS_ACCOUNT_ID" "AWS_REGION" "TF_SUBNET_IDS")
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

# --- Step 1: Set Terraform Variables ---
log "Step 1: Setting Terraform environment variables..."
cd "$SCRIPT_DIR"
chmod +x set-tf-vars.sh
eval $("./set-tf-vars.sh") || error "Failed to set Terraform variables."
log "Terraform variables set in environment."

# --- Step 2: Deploy ECR Repository ---
log "Step 2: Deploying ECR repository with Terraform..."
cd "$TF_ECR_DIR"

terraform init -input=false || error "ECR Terraform init failed."
terraform apply -auto-approve -input=false || error "ECR Terraform apply failed."

ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
if [[ -z "$ECR_REPOSITORY_URL" ]]; then
  error "Failed to capture ecr_repository_url Terraform output."
fi
log "ECR Repository URL: $ECR_REPOSITORY_URL"

# --- Step 3: Build and Push Docker Image ---
log "Step 3: Building and pushing Docker image..."
cd "$SCRIPT_DIR"
chmod +x build.sh
./build.sh || error "Failed to build and push Docker image."
FINAL_IMAGE_URI="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
log "Docker image: $FINAL_IMAGE_URI"

# --- Step 4: Deploy Application Infrastructure ---
log "Step 4: Deploying application infrastructure with Terraform..."
cd "$TF_APP_DIR"

terraform init -input=false || error "App Terraform init failed."
terraform apply -auto-approve -input=false \
    -var="image_uri=${FINAL_IMAGE_URI}" \
    -var="ecs_cluster_arn=${ECS_CLUSTER_ARN}" \
    || error "App Terraform apply failed."

TASK_DEFINITION_ARN=$(terraform output -raw task_definition_arn)
SECURITY_GROUP_ID=$(terraform output -raw security_group_id)
CONTAINER_NAME=$(terraform output -raw container_name)
log "Task Definition ARN: $TASK_DEFINITION_ARN"

# --- Step 5: Run Test ---
log "Step 5: Building and running test..."
cd "$TEST_RUNNER_DIR"

log "Building test-runner Go application..."
go mod tidy || log "Warning: go mod tidy failed, continuing anyway"
go build -o test-runner . || error "Failed to build test-runner."

log "Executing test-runner..."
./test-runner \
    --cluster-arn="$ECS_CLUSTER_ARN" \
    --task-definition-arn="$TASK_DEFINITION_ARN" \
    --subnet-ids="$TF_SUBNET_IDS" \
    --security-group-id="$SECURITY_GROUP_ID" \
    --container-name="$CONTAINER_NAME" \
    --input='{"message": "Hello from E2E test!", "data": {"test": true}}' \
    || error "Test runner failed."

log "Test completed successfully!"

# --- Step 6: Cleanup ---
if [[ "$PERFORM_CLEANUP" == true ]]; then
  log "Step 6: Cleaning up infrastructure with Terraform..."

  log "Destroying application infrastructure (02-app)..."
  cd "$TF_APP_DIR"
  terraform destroy -auto-approve -input=false || error "App Terraform destroy failed."

  log "Destroying ECR repository (01-ecr)..."
  cd "$TF_ECR_DIR"
  terraform destroy -auto-approve -input=false || error "ECR Terraform destroy failed."

  log "Infrastructure cleaned up successfully."
  log "Note: Shared infrastructure (infra/terraform) was NOT destroyed."
else
  log "Step 6: Skipping cleanup as requested."
fi

log "E2E script completed successfully!"
exit 0
