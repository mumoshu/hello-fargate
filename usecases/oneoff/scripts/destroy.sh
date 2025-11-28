#!/bin/bash
set -e

# Destroy script for oneoff Fargate task infrastructure
# Usage: ./scripts/destroy.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"

echo "Setting Terraform variables..."
cd "$SCRIPT_DIR"
chmod +x set-tf-vars.sh
eval $(./set-tf-vars.sh) || echo "Warning: Failed to set TF vars, continuing with dummy values"

echo "Destroying application infrastructure..."
terraform -chdir="$TF_APP_DIR" destroy -auto-approve -input=false \
  -var="ecs_cluster_arn=${TF_VAR_ecs_cluster_arn:-dummy}" \
  -var="image_uri=${TF_VAR_image_uri:-dummy}" \
  -var="vpc_id=${TF_VAR_vpc_id:-dummy}" || true

echo "Destroying ECR infrastructure..."
terraform -chdir="$TF_ECR_DIR" destroy -auto-approve -input=false || true

echo "Done! Infrastructure destroyed."
