#!/bin/bash
set -e

# Apply script for batchjobs Fargate infrastructure
# Usage: ./scripts/apply.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
TF_ECR_DIR="$PROJECT_ROOT/infra/terraform/01-ecr"
TF_APP_DIR="$PROJECT_ROOT/infra/terraform/02-app"

echo "Applying ECR infrastructure..."
terraform -chdir="$TF_ECR_DIR" init -input=false
terraform -chdir="$TF_ECR_DIR" apply -auto-approve -input=false

echo "Building and pushing Docker image..."
cd "$SCRIPT_DIR"
chmod +x build.sh
./build.sh

echo "Setting Terraform variables..."
chmod +x set-tf-vars.sh
eval $(./set-tf-vars.sh)

echo "Applying Batch infrastructure..."
terraform -chdir="$TF_APP_DIR" init -input=false
terraform -chdir="$TF_APP_DIR" apply -auto-approve -input=false

# Wait for IAM roles to be ready (IAM propagation delay)
echo "Waiting for IAM roles to propagate..."

# Verify roles exist
MAX_ATTEMPTS=12
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "Checking IAM role readiness (attempt $ATTEMPT/$MAX_ATTEMPTS)..."

    # Check if the execution role can be retrieved
    if aws iam get-role --role-name "hello-fargate-batchjobs-execution-role" >/dev/null 2>&1; then
        # Also check the service role
        if aws iam get-role --role-name "hello-fargate-batchjobs-service-role" >/dev/null 2>&1; then
            echo "IAM roles are ready."
            break
        fi
    fi

    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "Warning: IAM role check timed out, proceeding anyway..."
        break
    fi

    sleep 5
done

echo "Done! Infrastructure applied successfully."
terraform -chdir="$TF_APP_DIR" output
