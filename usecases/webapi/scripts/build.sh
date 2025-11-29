#!/bin/bash
set -e

# Build script for webapi use case
# Builds and pushes the API Docker image to ECR

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"

# Get AWS region
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-northeast-1")}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"

# Get ECR repository URL
REPO_URL=$(terraform -chdir="$TF_ECR_DIR" output -raw repository_url 2>/dev/null)

if [ -z "$REPO_URL" ]; then
    echo "Error: ECR repository not found. Run apply.sh first."
    exit 1
fi

echo "Building Docker image..."

# Build API image
echo "Building API image..."
docker build -t hello-fargate-webapi-app:latest "$PROJECT_ROOT/apps/api"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Tag and push
echo "Pushing image to ECR..."
docker tag hello-fargate-webapi-app:latest "${REPO_URL}:latest"
docker push "${REPO_URL}:latest"

echo "Build and push complete!"
echo "  Image: ${REPO_URL}:latest"
