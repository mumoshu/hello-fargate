#!/bin/bash
# Generate TF_VAR_* exports for webapp use case
# Usage: eval $(./set-tf-vars.sh)

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"

# Get AWS region and account ID
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-northeast-1")}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"

# Get ECR repository URL from terraform output (if deployed)
if [ -f "$TF_ECR_DIR/terraform.tfstate" ]; then
    REPO_URL=$(terraform -chdir="$TF_ECR_DIR" output -raw repository_url 2>/dev/null || echo "")
fi

# Fall back to constructed URL if not available
if [ -z "$REPO_URL" ]; then
    REPO_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hello-fargate-webapp-app"
fi

# VPC ID (required - set via TF_VPC_ID environment variable or use default VPC)
if [ -z "$TF_VPC_ID" ]; then
    TF_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
fi

# ECS Cluster ARN (use shared cluster from infra/)
SHARED_INFRA_DIR=$(realpath "$PROJECT_ROOT/../../infra/terraform")
if [ -f "$SHARED_INFRA_DIR/terraform.tfstate" ]; then
    ECS_CLUSTER_ARN=$(terraform -chdir="$SHARED_INFRA_DIR" output -raw ecs_cluster_arn 2>/dev/null || echo "")
fi

# Export variables
echo "export TF_VAR_image_uri=\"${REPO_URL}:latest\""
echo "export TF_VAR_vpc_id=\"${TF_VPC_ID}\""
echo "export TF_VAR_ecs_cluster_arn=\"${ECS_CLUSTER_ARN}\""
