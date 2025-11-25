#!/bin/bash
set -e

# Use environment variables if set, otherwise use placeholders (which will likely fail)
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-"YOUR_AWS_ACCOUNT_ID"}
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Check if placeholder values are still being used
if [[ "$AWS_ACCOUNT_ID" == "YOUR_AWS_ACCOUNT_ID" ]] || [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "Error: AWS_ACCOUNT_ID environment variable is not set or is still the placeholder." >&2
    echo "Please set it in your environment (e.g., in .env.local and source it)." >&2
    exit 1
fi
if [[ "$AWS_REGION" == "us-east-1" ]] && [[ -z "$AWS_REGION" ]]; then
    # Allow default region if AWS_REGION is not explicitly set
    echo "Warning: AWS_REGION environment variable not set, defaulting to us-east-1." >&2
    AWS_REGION="us-east-1"
elif [[ -z "$AWS_REGION" ]]; then
    echo "Error: AWS_REGION environment variable is not set." >&2
     echo "Please set it in your environment (e.g., in .env.local and source it)." >&2
     exit 1
fi

IMAGE_NAME="fargate-workflow-app"
IMAGE_TAG="latest"

ECR_REPOSITORY_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_NAME"

# Navigate to the app directory
cd ../app

# Build the Go application statically
# Using CGO_ENABLED=0 ensures a static binary suitable for a minimal container image (like alpine or scratch)
echo "Building Go application..."
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Build the Docker image
# TODO: Create a Dockerfile in the app/ directory
echo "Building Docker image..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# Authenticate Docker to ECR
# Needs AWS CLI configured
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Tag the image
echo "Tagging image for ECR..."
docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REPOSITORY_URI:$IMAGE_TAG

# Push the image to ECR
echo "Pushing image to ECR..."
docker push $ECR_REPOSITORY_URI:$IMAGE_TAG

echo "Build and push complete: $ECR_REPOSITORY_URI:$IMAGE_TAG"

# Clean up the binary
rm main 