# One-off Tasks on Fargate - Run-once ECS Tasks

This project demonstrates running one-off containerized tasks on AWS Fargate.

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Test Runner   │─────▶│   ECS RunTask   │─────▶│  Fargate Task   │
│   (trigger)     │      │   API Call      │      │  (runs & exits) │
└─────────────────┘      └─────────────────┘      └────────┬────────┘
                                                           │
                                                           ▼
                                                  ┌─────────────────┐
                                                  │ CloudWatch Logs │
                                                  │  (task output)  │
                                                  └─────────────────┘
```

## Implementation

**Execution Model:** Single ECS task run, exits when done

**App Pattern:**
```go
func main() {
    // Get input from environment
    inputJSON := os.Getenv("TASK_INPUT")

    // Process input
    var input TaskInput
    json.Unmarshal([]byte(inputJSON), &input)

    // Do work...

    // Output result to stdout (captured in CloudWatch)
    output, _ := json.MarshalIndent(result, "", "  ")
    fmt.Println(string(output))
}
```

**Terraform Resources:**
- `aws_ecs_task_definition` - Task definition only (no service)
- `aws_security_group` - Outbound-only
- `aws_cloudwatch_log_group` - For task logs
- `aws_iam_role` - Execution role + task role

**Test Pattern:** Run task via ECS RunTask API, wait for STOPPED, check exit code & logs

## Components

- `apps/task/` - Go application that processes input and outputs results
- `infra/terraform/01-ecr/` - ECR repository for container images
- `infra/terraform/02-app/` - ECS task definition, IAM roles, security group
- `scripts/` - Build, deploy, and test scripts
- `tests/taskrun/` - Test runner to execute tasks and verify results

## Quick Start

```bash
# Set required environment variables
export AWS_ACCOUNT_ID="your-account-id"
export AWS_REGION="ap-northeast-1"
export TF_VPC_ID="vpc-xxxxx"

# Run end-to-end test
./scripts/run-e2e.sh

# Or run without cleanup for debugging
./scripts/run-e2e.sh --no-cleanup
```

## Manual Deployment

```bash
# Deploy infrastructure
./scripts/apply.sh

# Run a task manually
cd tests/taskrun
go build -o test-runner .
./test-runner \
    --cluster-arn="$ECS_CLUSTER_ARN" \
    --task-definition-arn="$TASK_DEF_ARN" \
    --subnet-ids="$SUBNET_IDS" \
    --security-group-id="$SG_ID" \
    --container-name="hello-fargate-oneoff-app-container" \
    --input='{"message": "Hello!"}'
```

## Cleanup

```bash
./scripts/destroy.sh
```

## Related Documentation

- [Amazon ECS RunTask API](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_RunTask.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [Fargate Launch Type](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
