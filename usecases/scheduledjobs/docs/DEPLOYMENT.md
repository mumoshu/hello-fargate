# Manual Setup and Deployment

These steps describe how to manually build the application container, set up environment variables for Terraform, and deploy the AWS infrastructure.

**(Ensure required environment variables are loaded as described in [ENVIRONMENT.md](./ENVIRONMENT.md))**

1.  **Customize Go App (Optional):**
    *   If needed, modify the Go application logic in `app/main.go`.
    *   Ensure the logic handles two scenarios:
        *   **Initial Task:** When run as the first step, it should output a JSON string to standard output containing a `parallelItems` array. Example: `{"message": "Initial task done", "parallelItems": [{"id": 1}, {"id": 2}]}`.
        *   **Parallel Task:** When run within the Step Functions Map state, it receives an item from the `parallelItems` array as input. It should process this item and output its result as a JSON string to standard output.

2.  **Build and Push Docker Image:**
    *   Navigate to the scripts directory:
        ```bash
        cd terraform/fargate-scheduled-workflow/scripts 
        # Or adjust path relative to your current directory
        ```
    *   **Important:** The build script uses `AWS_ACCOUNT_ID` and `AWS_REGION` from your environment to tag and push the image to the correct ECR repository. It also uses `IMAGE_TAG` if set (defaults to `latest`).
    *   Make the script executable:
        ```bash
        chmod +x build.sh
        ```
    *   Run the script:
        ```bash
        ./build.sh
        ```
    *   This script performs several actions:
        *   Builds the Go application (`app/main.go`).
        *   Builds the Docker image using `app/Dockerfile`.
        *   Logs in to the AWS ECR registry.
        *   Tags the image appropriately (e.g., `<aws_account_id>.dkr.ecr.<aws_region>.amazonaws.com/<prefix>-app:<tag>`).
        *   Pushes the tagged image to your ECR repository (which will be created by Terraform if it doesn't exist).

3.  **Set Terraform Environment Variables:**
    *   Terraform needs certain configuration values passed as environment variables prefixed with `TF_VAR_`. A helper script converts the standard environment variables (like `AWS_REGION`, `TF_SUBNET_IDS`) into the required format.
    *   Navigate to the project root or ensure the script path is correct relative to your location.
    *   Run the helper script and evaluate its output in your current shell session:
        ```bash
        eval $(./terraform/fargate-scheduled-workflow/scripts/set-tf-vars.sh)
        ```
        *(Alternatively, you can use `source <(./terraform/fargate-scheduled-workflow/scripts/set-tf-vars.sh)`)*
    *   This sets variables like `TF_VAR_aws_region`, `TF_VAR_subnet_ids`, `TF_VAR_image_uri`, etc., making them available to Terraform commands.

4.  **Deploy Infrastructure with Terraform:**
    *   Navigate to the Terraform configuration directory:
        ```bash
        cd terraform/fargate-scheduled-workflow/terraform 
        # Or adjust path relative to your current directory
        ```
    *   Initialize Terraform (downloads required providers):
        ```bash
        terraform init
        ```
    *   Review the planned infrastructure changes (optional but recommended):
        ```bash
        terraform plan
        ```
    *   Apply the Terraform configuration to create the AWS resources:
        ```bash
        terraform apply -auto-approve
        ```
        *(Remove `-auto-approve` if you want to review the changes and manually confirm before applying)*
    *   Terraform will output values upon successful completion. **Note the `state_machine_arn` output value**, as you will need it for manual testing. 