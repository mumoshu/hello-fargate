#!/bin/bash
set -e

# Apply script for webapi use case
# Deploys ECR repository, builds image, and deploys app infrastructure

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

# Step 2: Deploy ECR repository
echo "Applying ECR infrastructure..."
terraform -chdir="$TF_ECR_DIR" init -input=false
terraform -chdir="$TF_ECR_DIR" apply -auto-approve -input=false

# Step 3: Build and push Docker image
echo "Building and pushing Docker image..."
cd "$SCRIPT_DIR"
chmod +x build.sh
./build.sh

# Step 4: Set Terraform variables
echo "Setting Terraform variables..."
chmod +x set-tf-vars.sh
eval $(./set-tf-vars.sh)

# Step 5: Deploy application infrastructure (ALB, Cognito, ECS)
echo "Applying application infrastructure..."
terraform -chdir="$TF_APP_DIR" init -input=false
terraform -chdir="$TF_APP_DIR" apply -auto-approve -input=false

# Step 6: Wait for ALB and ECS service to stabilize
echo "Waiting for infrastructure to stabilize..."
sleep 10

# Check service status
ECS_CLUSTER_ARN="$TF_VAR_ecs_cluster_arn"
SERVICE_NAME=$(terraform -chdir="$TF_APP_DIR" output -raw ecs_service_name 2>/dev/null)

echo "Waiting for ECS service to have running task..."
for i in {1..30}; do
    RUNNING=$(aws ecs describe-services --cluster "$ECS_CLUSTER_ARN" --services "$SERVICE_NAME" --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
    if [ "$RUNNING" -ge 1 ]; then
        echo "ECS service has $RUNNING running task(s)."
        break
    fi
    echo "  Waiting... ($RUNNING/1 tasks running)"
    sleep 10
done

# Wait for ALB target to be healthy
ALB_TG_ARN=$(terraform -chdir="$TF_APP_DIR" output -raw target_group_arn 2>/dev/null)
echo "Waiting for ALB target to be healthy..."
for i in {1..30}; do
    HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$ALB_TG_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text 2>/dev/null || echo "unknown")
    if [ "$HEALTHY" = "healthy" ]; then
        echo "ALB target is healthy."
        break
    fi
    echo "  Waiting... (target health: $HEALTHY)"
    sleep 10
done

echo "Done! Infrastructure applied successfully."
echo ""
echo "=== Outputs ==="
terraform -chdir="$TF_APP_DIR" output
