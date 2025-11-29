#!/bin/bash
set -e

# Apply script for backend use case
# Deploys ECR repositories, builds images, and deploys app infrastructure

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"
SHARED_INFRA_DIR=$(realpath "$PROJECT_ROOT/../../infra/terraform")

# Step 1: Deploy shared infrastructure if needed
if [ -d "$SHARED_INFRA_DIR" ]; then
    if [ ! -f "$SHARED_INFRA_DIR/terraform.tfstate" ]; then
        echo "Deploying shared ECS cluster infrastructure..."
        terraform -chdir="$SHARED_INFRA_DIR" init -input=false
        terraform -chdir="$SHARED_INFRA_DIR" apply -auto-approve -input=false
    fi
fi

# Step 2: Deploy ECR repositories
echo "Applying ECR infrastructure..."
terraform -chdir="$TF_ECR_DIR" init -input=false
terraform -chdir="$TF_ECR_DIR" apply -auto-approve -input=false

# Step 3: Build and push Docker images
echo "Building and pushing Docker images..."
cd "$SCRIPT_DIR"
chmod +x build.sh
./build.sh

# Step 4: Set Terraform variables
echo "Setting Terraform variables..."
chmod +x set-tf-vars.sh
eval $(./set-tf-vars.sh)

# Step 5: Deploy application infrastructure
echo "Applying application infrastructure..."
terraform -chdir="$TF_APP_DIR" init -input=false
terraform -chdir="$TF_APP_DIR" apply -auto-approve -input=false

# Step 6: Wait for services to stabilize
echo "Waiting for ECS services to stabilize..."
sleep 10

# Check service status
ECS_CLUSTER_ARN="$TF_VAR_ecs_cluster_arn"
BACKEND_SERVICE=$(terraform -chdir="$TF_APP_DIR" output -raw backend_service_name 2>/dev/null)
FRONTEND_SERVICE=$(terraform -chdir="$TF_APP_DIR" output -raw frontend_service_name 2>/dev/null)

echo "Waiting for backend service to have 2 running tasks..."
for i in {1..30}; do
    RUNNING=$(aws ecs describe-services --cluster "$ECS_CLUSTER_ARN" --services "$BACKEND_SERVICE" --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
    if [ "$RUNNING" -ge 2 ]; then
        echo "Backend service has $RUNNING running tasks."
        break
    fi
    echo "  Waiting... ($RUNNING/2 tasks running)"
    sleep 10
done

echo "Waiting for frontend service to have 1 running task..."
for i in {1..30}; do
    RUNNING=$(aws ecs describe-services --cluster "$ECS_CLUSTER_ARN" --services "$FRONTEND_SERVICE" --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
    if [ "$RUNNING" -ge 1 ]; then
        echo "Frontend service has $RUNNING running task(s)."
        break
    fi
    echo "  Waiting... ($RUNNING/1 tasks running)"
    sleep 10
done

echo "Done! Infrastructure applied successfully."
terraform -chdir="$TF_APP_DIR" output
