# Background Jobs on Fargate - SQS-driven Workers

This project demonstrates running background job workers on AWS Fargate that process messages from SQS.

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Producer      │─────▶│    SQS Queue    │─────▶│  ECS Service    │
│   (sends msgs)  │      │   (with DLQ)    │      │  (SQS poller)   │
└─────────────────┘      └─────────────────┘      └────────┬────────┘
                                │                          │
                                │ (failed msgs)            │ (process)
                                ▼                          ▼
                         ┌─────────────────┐      ┌─────────────────┐
                         │  Dead Letter    │      │ CloudWatch Logs │
                         │    Queue        │      │  (worker logs)  │
                         └─────────────────┘      └─────────────────┘
```

## Implementation

**Execution Model:** Long-running ECS Service polling SQS

**App Pattern:**
```go
func main() {
    queueURL := os.Getenv("SQS_QUEUE_URL")

    // Handle graceful shutdown
    ctx, cancel := context.WithCancel(context.Background())
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    go func() {
        <-sigChan
        cancel()
    }()

    // Main polling loop
    for {
        select {
        case <-ctx.Done():
            return
        default:
            pollAndProcess(ctx, sqsClient, queueURL)
        }
    }
}

func pollAndProcess(ctx context.Context, client *sqs.Client, queueURL string) {
    result, _ := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
        QueueUrl:            &queueURL,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds:     20,  // Long polling
        VisibilityTimeout:   300, // 5 minutes
    })

    for _, msg := range result.Messages {
        processMessage(ctx, client, queueURL, msg)
        // Delete on success
        client.DeleteMessage(ctx, &sqs.DeleteMessageInput{...})
    }
}
```

**Terraform Resources:**
- `aws_sqs_queue` - Main queue with redrive policy
- `aws_sqs_queue` - Dead letter queue (DLQ)
- `aws_ecs_task_definition` - Task definition
- `aws_ecs_service` - Long-running service (desired_count >= 1)
- `aws_iam_role_policy` - SQS permissions for task role

**Test Pattern:** Send message to SQS, verify processing via CloudWatch logs

## Components

- `apps/worker/` - Go application that polls SQS and processes messages
- `infra/terraform/01-ecr/` - ECR repository for container images
- `infra/terraform/02-app/` - ECS service, SQS queues, IAM roles, security group
- `scripts/` - Build, deploy, and test scripts
- `tests/sqstest/` - Test runner to send messages and verify processing

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

# Send a test message
cd tests/sqstest
go build -o test-runner .
./test-runner \
    --queue-url="$QUEUE_URL" \
    --log-group="/ecs/hello-fargate-backgroundjobs-task" \
    --cluster-arn="$ECS_CLUSTER_ARN" \
    --service-name="hello-fargate-backgroundjobs-service"
```

## Cleanup

```bash
./scripts/destroy.sh
```

## Related Documentation

- [Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html)
- [SQS Dead Letter Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [ECS Services](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html)
