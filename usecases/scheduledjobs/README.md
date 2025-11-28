# Hello Fargate for Scheduled Jobs

This project sets up a scheduled workflow using Fargate and other AWS services.

The workflow consists of tasks running a Go application containerized and executed on AWS Fargate.

## Overview

*   **Workflow Orchestration:** Uses AWS Step Functions to define and manage the workflow steps (Initial Step -> Parallel Map Step -> Success).
*   **Task Execution:** Leverages AWS Fargate to run containerized instances of the Go application for each workflow step.
*   **Scheduling:** An Amazon EventBridge rule triggers the Step Functions state machine periodically.
*   **Application:** A simple Go application (`app/`) designed to be run as a task, accepting input and producing output. The initial task is expected to output JSON with a `parallelItems` array, which the map state iterates over.
*   **Infrastructure:** Defined using Terraform (`terraform/`).
*   **Testing:** Includes a Go test runner (`test-runner/`) to manually trigger and monitor the workflow.

## Components

*   `apps/jobrunner`: Contains the source code for the Go application.
*   `terraform/`: Contains the Terraform code to provision the necessary AWS infrastructure (ECR, Fargate Task Definition, Step Functions State Machine, EventBridge Rule, IAM Roles, Security Group, etc.).
*   `scripts/`: Holds utility scripts, such as for building the Docker image for the Go app and pushing it to ECR.
*   `tests/jobrun`: Contains a Go application to manually trigger the Step Functions workflow and observe its output.

## Environment Setup

Before running the setup steps, ensure your environment has the necessary AWS credentials configured for the AWS CLI to authenticate.

Additionally, you need to set several environment variables (like `AWS_ACCOUNT_ID`, `AWS_REGION`, `TF_SUBNET_IDS`). These are used by the scripts and Terraform.

See the detailed guide for a list of required and optional variables and how to set them: [Environment Setup](./docs/ENVIRONMENT.md).

**How to find Subnet IDs for `TF_SUBNET_IDS`:**

The Fargate tasks require subnets with outbound internet access (e.g., public subnets or private subnets with a NAT Gateway) to pull images from ECR and send logs to CloudWatch.

See the detailed guide for instructions on finding suitable subnet IDs using the AWS CLI or Console: [Finding Subnet IDs](./docs/FINDING_SUBNETS.md).

Choose at least two subnet IDs from different Availability Zones for high availability and list them comma-separated in your environment:
`export TF_SUBNET_IDS="subnet-11111111,subnet-22222222"`

*(Note: If using private subnets, ensure they have appropriate routes/endpoints. See the linked guide for details).*

**Ensure these variables are loaded into your shell session before proceeding.**

## Setup and Deployment

While the [End-to-End Test Script](#end-to-end-test-script) is the recommended way to deploy and test, you can also perform the steps manually.

**(Ensure environment variables are set as described in [Environment Setup](./docs/ENVIRONMENT.md))**

The manual process involves:
1.  **(Optional)** Customizing the Go application in `app/`.
2.  Building and pushing the Docker image using the `scripts/build.sh` script.
3.  Setting `TF_VAR_...` environment variables using the `scripts/set-tf-vars.sh` script.
4.  Deploying the infrastructure using `terraform init` and `terraform apply` in the `terraform/` directory.

See the detailed guide for step-by-step instructions: [Manual Setup and Deployment](./docs/DEPLOYMENT.md).

Remember to note the `state_machine_arn` output by Terraform if deploying manually.

## Running the Workflow Manually (Testing)

After deployment, you can manually trigger the workflow using the Go test runner located in `test-runner/`.

The test runner supports three modes:
- **Direct mode**: Directly starts a Step Functions execution
- **EventBridge mode**: Sends a custom event to EventBridge to trigger the workflow
- **Scheduled mode**: Creates a temporary scheduled EventBridge rule to trigger the workflow

This involves building the test runner and executing it with the State Machine ARN.

See the detailed guide for instructions: [Manual Workflow Testing](./docs/TESTING.md).

## End-to-End Test Script

The `scripts/run-e2e.sh` script automates the entire process: building the image, deploying infrastructure, running a test workflow execution, and optionally cleaning up.

This is the recommended way to quickly verify the setup.

See the detailed guide for prerequisites and usage instructions: [End-to-End Test Script](./docs/E2E_TESTING.md).

## Cleanup

If you ran the E2E script without the `--no-cleanup` flag, cleanup is handled automatically. 

If you deployed manually or skipped cleanup in the E2E script:

1.  **Destroy Infrastructure:**
    *   Navigate to the Terraform directory: `cd terraform/fargate-scheduled-workflow/terraform`
    *   Ensure the `TF_VAR_...` variables are set by re-running:
        `eval $(../scripts/set-tf-vars.sh)`
    *   Run: `terraform destroy -auto-approve`
        *(Remove `-auto-approve` to review before destroying)*
2.  **Delete ECR Images (Optional):**
    *   Go to the AWS ECR console and manually delete the images pushed to the ECR repository (name derived from `TF_VAR_prefix` or default `fargate-workflow-app`). 
