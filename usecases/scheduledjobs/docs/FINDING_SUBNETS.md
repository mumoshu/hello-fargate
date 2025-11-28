# Finding Subnet IDs for Fargate Tasks (`TF_SUBNET_IDS`)

The Fargate tasks defined in this project need to run in subnets that allow outbound network access to AWS services like ECR (to pull the container image) and CloudWatch Logs (for logging). Often, using the **public subnets** within your default VPC is the simplest approach, assuming your security policies allow it.

You can use the AWS CLI to help identify suitable subnet IDs. Ensure your `AWS_REGION` is correctly set in your environment before running these commands.

1.  **Find your Default VPC ID and store it:**
    ```bash
    export VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
    echo "Using VPC_ID: $VPC_ID"
    ```
    This command finds the default VPC ID and stores it in the `VPC_ID` environment variable for the current shell session.

2.  **List Subnets in that VPC:**
    Use the `VPC_ID` variable obtained above to list its subnets:
    ```bash
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}" --output table
    ```
    *(This command now automatically uses the VPC ID found in step 1)*

3.  **Set Subnet IDs (`TF_SUBNET_IDS`):**
    You need to provide at least two subnet IDs (preferably in different Availability Zones for high availability) for the `TF_SUBNET_IDS` environment variable. Use the output from Step 2 to find suitable subnets, focusing on those where the `Public` column is `true`.

    **Option A: Manual Selection**
    1.  Identify two or more Subnet IDs from the table output in Step 2 where `Public` is `true`.
    2.  Set the environment variable in your shell or `.env.local` file, replacing the example IDs with your chosen ones:
        ```bash
        export TF_SUBNET_IDS="subnet-11111111,subnet-22222222"
        ```

    **Option B: Automated Selection (First two public subnets)**
    This command attempts to automatically find the first two subnets in your default VPC that have `MapPublicIpOnLaunch` set to true and exports them as `TF_SUBNET_IDS`. *Verify the selected subnets meet your requirements.*
    ```bash
    export TF_SUBNET_IDS=$( \
      aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
      --query "Subnets[0:2].SubnetId" --output text | \
      tr '\t' ',' \
    )
    echo "Automatically set TF_SUBNET_IDS to: $TF_SUBNET_IDS"
    ```

*(Note: If you must use private subnets, ensure they have a route to a NAT Gateway or appropriate VPC Endpoints for required services like ECR (`com.amazonaws.<region>.ecr.dkr`, `com.amazonaws.<region>.ecr.api`), CloudWatch Logs (`com.amazonaws.<region>.logs`), and STS (`com.amazonaws.<region>.sts`). You will need to set `TF_SUBNET_IDS` manually in this case.)* 