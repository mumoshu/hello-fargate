#!/bin/bash

# This script generates environment variables for Terraform (TF_VAR_...) based on
# standard environment variables.
# Run this script within the context of your shell before running terraform commands:
# eval $(./scripts/set-tf-vars.sh)

# --- Required Environment Variables ---

# Check for required variables
required_vars=("AWS_ACCOUNT_ID" "AWS_REGION" "TF_VPC_ID")
missing_vars=()
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -ne 0 ]]; then
    echo "Error: Missing required environment variables:" >&2
    for var in "${missing_vars[@]}"; do
        echo "  - $var" >&2
    done
    echo "Please set them (e.g., in .env.local) and ensure they are loaded." >&2
    exit 1
fi

# --- Construct TF_VAR values ---

# 1. TF_VAR_image_uri
IMAGE_NAME="hello-fargate-backgroundjobs-app"
IMAGE_TAG=${IMAGE_TAG:-"latest"}
TF_VAR_image_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"
echo "export TF_VAR_image_uri=\"${TF_VAR_image_uri}\""

# 2. TF_VAR_vpc_id
echo "export TF_VAR_vpc_id=\"${TF_VPC_ID}\""

# 3. TF_VAR_ecs_cluster_arn (fetch from shared infra or use environment variable)
if [[ -n "$TF_ECS_CLUSTER_ARN" ]]; then
    echo "export TF_VAR_ecs_cluster_arn=\"${TF_ECS_CLUSTER_ARN}\""
else
    # Try to fetch from shared infra terraform output
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    SHARED_INFRA_DIR="$SCRIPT_DIR/../../../infra/terraform"
    if [[ -d "$SHARED_INFRA_DIR" ]] && [[ -f "$SHARED_INFRA_DIR/terraform.tfstate" ]]; then
        ECS_CLUSTER_ARN=$(cd "$SHARED_INFRA_DIR" && terraform output -raw ecs_cluster_arn 2>/dev/null)
        if [[ -n "$ECS_CLUSTER_ARN" ]]; then
            echo "export TF_VAR_ecs_cluster_arn=\"${ECS_CLUSTER_ARN}\""
        else
            echo "Error: Could not fetch ecs_cluster_arn from shared infra. Set TF_ECS_CLUSTER_ARN manually." >&2
            exit 1
        fi
    else
        echo "Error: Shared infra not deployed. Deploy infra/terraform first or set TF_ECS_CLUSTER_ARN manually." >&2
        exit 1
    fi
fi

# --- Optional Environment Variables ---

# 4. TF_VAR_security_group_ids (additional SGs)
if [[ -n "$TF_EXTRA_SG_IDS" ]]; then
    IFS=',' read -r -a sg_array <<< "$TF_EXTRA_SG_IDS"
    json_sgs=$(printf '%s\n' "${sg_array[@]}" | jq -R . | jq -s .)
    echo "export TF_VAR_security_group_ids='${json_sgs}'"
else
    echo "export TF_VAR_security_group_ids='[]'"
fi

# 5. TF_VAR_task_cpu
if [[ -n "$TF_TASK_CPU" ]]; then
    echo "export TF_VAR_task_cpu=${TF_TASK_CPU}"
fi

# 6. TF_VAR_task_memory
if [[ -n "$TF_TASK_MEMORY" ]]; then
    echo "export TF_VAR_task_memory=${TF_TASK_MEMORY}"
fi

# 7. TF_VAR_desired_count (number of worker instances)
if [[ -n "$TF_DESIRED_COUNT" ]]; then
    echo "export TF_VAR_desired_count=${TF_DESIRED_COUNT}"
fi
