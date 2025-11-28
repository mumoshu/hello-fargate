#!/bin/bash
set -e

# Use environment variables if set, otherwise use placeholders
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"YOUR_AWS_ACCOUNT_ID"}
AWS_REGION=${AWS_REGION:-"ap-northeast-1"}

# Check if placeholder values are still being used
if [[ "$AWS_ACCOUNT_ID" == "YOUR_AWS_ACCOUNT_ID" ]] || [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "Error: AWS_ACCOUNT_ID environment variable is not set or is still the placeholder." >&2
    echo "Please set it in your environment (e.g., in .env.local and source it)." >&2
    exit 1
fi

IMAGE_NAME="hello-fargate-backgroundjobs-app"
IMAGE_TAG="latest"

ECR_REPOSITORY_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME"

# Navigate to the app directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR/../apps/worker"

# Build the Docker image
echo "Building Docker image..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# Authenticate Docker to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Tag the image
echo "Tagging image for ECR..."
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REPOSITORY_URI:$IMAGE_TAG

# Push the image to ECR
echo "Pushing image to ECR..."
docker push $ECR_REPOSITORY_URI:$IMAGE_TAG

echo "Build and push complete: $ECR_REPOSITORY_URI:$IMAGE_TAG"
