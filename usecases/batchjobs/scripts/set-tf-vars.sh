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
IMAGE_NAME="hello-fargate-batchjobs-app"
IMAGE_TAG=${IMAGE_TAG:-"latest"}
TF_VAR_image_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"
echo "export TF_VAR_image_uri=\"${TF_VAR_image_uri}\""

# 2. TF_VAR_vpc_id
echo "export TF_VAR_vpc_id=\"${TF_VPC_ID}\""

# NOTE: No TF_VAR_ecs_cluster_arn - AWS Batch manages its own compute

# --- Optional Environment Variables ---

# 3. TF_VAR_security_group_ids (additional SGs)
if [[ -n "$TF_EXTRA_SG_IDS" ]]; then
    IFS=',' read -r -a sg_array <<< "$TF_EXTRA_SG_IDS"
    json_sgs=$(printf '%s\n' "${sg_array[@]}" | jq -R . | jq -s .)
    echo "export TF_VAR_security_group_ids='${json_sgs}'"
else
    echo "export TF_VAR_security_group_ids='[]'"
fi

# 4. TF_VAR_max_vcpus
if [[ -n "$TF_MAX_VCPUS" ]]; then
    echo "export TF_VAR_max_vcpus=${TF_MAX_VCPUS}"
fi

# 5. TF_VAR_job_vcpu
if [[ -n "$TF_JOB_VCPU" ]]; then
    echo "export TF_VAR_job_vcpu=\"${TF_JOB_VCPU}\""
fi

# 6. TF_VAR_job_memory
if [[ -n "$TF_JOB_MEMORY" ]]; then
    echo "export TF_VAR_job_memory=${TF_JOB_MEMORY}"
fi
