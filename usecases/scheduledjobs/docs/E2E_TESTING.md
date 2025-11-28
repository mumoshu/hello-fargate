# End-to-End Test Script (`run-e2e.sh`)

A script (`scripts/run-e2e.sh`) is provided to automate the entire workflow: building the container image, deploying the necessary AWS infrastructure, running a test execution of the workflow, and optionally cleaning up (destroying the infrastructure).

This is the recommended way to quickly test the entire setup.

### Prerequisites

1.  **Tools:** Ensure all required command-line tools are installed and accessible in your PATH:
    *   `docker`
    *   `go` (~> 1.19)
    *   `terraform` (~> 1.2.0)
    *   `aws` CLI
    *   `jq` (for processing JSON output in the script)
2.  **Environment:** Make sure your AWS credentials are configured (e.g., via `~/.aws/credentials` or environment variables) and that the required environment variables (`AWS_ACCOUNT_ID`, `AWS_REGION`, `TF_SUBNET_IDS`, etc.) are loaded into your shell session.
    *   See [Environment Setup](./ENVIRONMENT.md) for details on required variables.

### Running the Script

1.  **Navigate:** Change to the `scripts` directory from the project root:
    ```bash
    cd terraform/fargate-scheduled-workflow/scripts
    ```
2.  **Make Executable:** Ensure the script has execute permissions:
    ```bash
    chmod +x run-e2e.sh
    ```
3.  **Execute:**
    *   To run all steps **including cleanup** (Terraform destroy) at the end:
        ```bash
        ./run-e2e.sh
        ```
    *   To run all steps **except** the final cleanup:
        ```bash
        ./run-e2e.sh --no-cleanup
        ```

### Script Actions

The `run-e2e.sh` script performs the following actions in sequence:

1.  **Sanity Checks:** Verifies the presence of required tools and environment variables.
2.  **Build & Push Image:** Executes `./build.sh` to build the Go app's Docker image and push it to ECR.
3.  **Set Terraform Variables:** Executes `./set-tf-vars.sh` to export the necessary `TF_VAR_...` variables for Terraform.
4.  **Deploy Infrastructure:** Navigates to the `../terraform` directory and runs `terraform init` followed by `terraform apply -auto-approve`.
5.  **Run Test Workflows:** Navigates to the `../test-runner` directory, builds the test runner (`go build`), and executes it three times:
    - First test: Direct Step Functions execution mode
    - Second test: EventBridge trigger mode (sends a custom event to trigger the workflow)
    - Third test: Scheduled EventBridge trigger mode (creates temporary scheduled rule, waits ~1.5 minutes) - can be skipped by setting `SKIP_SCHEDULED_TEST=true`
6.  **Cleanup (Optional):** If the `--no-cleanup` flag was *not* provided, it navigates back to the `../terraform` directory and runs `terraform destroy -auto-approve`. 