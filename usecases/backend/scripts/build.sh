#!/bin/bash
set -e

# Build script for backend use case
# Builds and pushes both backend and frontend Docker images to ECR

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"

# Get AWS region
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-northeast-1")}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"

# Get ECR repository URLs
BACKEND_REPO_URL=$(terraform -chdir="$TF_ECR_DIR" output -raw backend_repository_url 2>/dev/null)
FRONTEND_REPO_URL=$(terraform -chdir="$TF_ECR_DIR" output -raw frontend_repository_url 2>/dev/null)

if [ -z "$BACKEND_REPO_URL" ] || [ -z "$FRONTEND_REPO_URL" ]; then
    echo "Error: ECR repositories not found. Run apply.sh first."
    exit 1
fi

echo "Building Docker images..."

# Build backend image
echo "Building backend image..."
docker build -t hello-fargate-backend-backend:latest "$PROJECT_ROOT/apps/backend"

# Build frontend image
echo "Building frontend image..."
docker build -t hello-fargate-backend-frontend:latest "$PROJECT_ROOT/apps/frontend"

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Tag and push backend
echo "Pushing backend image to ECR..."
docker tag hello-fargate-backend-backend:latest "${BACKEND_REPO_URL}:latest"
docker push "${BACKEND_REPO_URL}:latest"

# Tag and push frontend
echo "Pushing frontend image to ECR..."
docker tag hello-fargate-backend-frontend:latest "${FRONTEND_REPO_URL}:latest"
docker push "${FRONTEND_REPO_URL}:latest"

echo "Build and push complete!"
echo "  Backend: ${BACKEND_REPO_URL}:latest"
echo "  Frontend: ${FRONTEND_REPO_URL}:latest"
