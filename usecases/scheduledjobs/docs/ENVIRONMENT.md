# Environment Setup

Before running the setup steps (either manually or using the E2E script), ensure your environment has the necessary AWS credentials and configuration loaded. The AWS CLI needs to be able to authenticate (e.g., via environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, or via an assumed role, instance profile, or configured `~/.aws/credentials` file).

Additionally, set the following environment variables. One common way to manage these is using a `.env.local` file in the project root (which can be loaded automatically if you use a tool like `direnv`):

```bash
# .env.local (Example - Fill in your actual values)

# --- Required --- 

# Your 12-digit AWS Account ID
export AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"

# The AWS Region where resources will be deployed (e.g., us-east-1, eu-west-2)
export AWS_REGION="us-east-1"

# Comma-separated list of Subnet IDs for Fargate tasks.
# These subnets need outbound internet access (e.g., public subnets or private
# subnets with a NAT Gateway). Choose at least two from different AZs.
# See ./FINDING_SUBNETS.md for help finding these.
export TF_SUBNET_IDS="subnet-xxxxxxxxxxxxxxxxx,subnet-yyyyyyyyyyyyyyyyy"

# --- Optional --- 

# If using named AWS profiles instead of default credentials
# export AWS_PROFILE="your-profile-name"

# Tag for the Docker image built by scripts/build.sh (defaults to 'latest')
# export IMAGE_TAG="v1.0.0"

# Comma-separated list of *additional* Security Group IDs to attach to Fargate tasks
# export TF_EXTRA_SG_IDS="sg-zzzzzzzzzzzzzzzzz"

# Prefix for created AWS resource names (e.g., ECR repo, Step Function)
# (Defaults to 'fargate-workflow')
# export TF_PREFIX="my-fargate-flow"

# EventBridge schedule expression for triggering the workflow
# (Defaults to 'rate(1 hour)') See: 
# https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schedule-expressions.html
# export TF_SCHEDULE="rate(2 hours)"

# Fargate task CPU units (Defaults to 256 - 0.25 vCPU)
# See: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-configurations.html
# export TF_TASK_CPU=512 # (0.5 vCPU)

# Fargate task Memory in MiB (Defaults to 512 - 0.5 GB)
# Must be compatible with the chosen CPU value.
# export TF_TASK_MEMORY=1024 # (1 GB)
```

**Important:** Ensure these variables are exported and available in your shell session *before* running the build, deployment, or E2E scripts.

Terraform also requires these values to be passed as `TF_VAR_...` variables. The `scripts/set-tf-vars.sh` script handles this conversion automatically by reading the standard environment variables (like `AWS_REGION`, `TF_SUBNET_IDS`) and exporting the corresponding `TF_VAR_...` variables needed by Terraform. 