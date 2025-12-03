# Batch Jobs on Fargate - AWS Batch Array Processing

This project demonstrates batch processing using AWS Batch with Fargate compute.

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Test Runner   │─────▶│  AWS Batch      │─────▶│    Fargate      │
│   (submit job)  │      │  Job Queue      │      │    Compute      │
└─────────────────┘      └─────────────────┘      │   Environment   │
                                │                 └────────┬────────┘
                                │                          │
                                ▼                          ▼
                         ┌─────────────────┐      ┌─────────────────┐
                         │  Job Definition │      │  Array Jobs     │
                         │  (container     │      │  [0] [1] [2]... │
                         │   config)       │      │  (parallel)     │
                         └─────────────────┘      └────────┬────────┘
                                                           │
                                                           ▼
                                                  ┌─────────────────┐
                                                  │ CloudWatch Logs │
                                                  │  (job output)   │
                                                  └─────────────────┘
```

## Implementation

**Execution Model:** AWS Batch Job Queue → Fargate Compute Environment

**App Pattern:**
```go
func main() {
    // Get array index (0, 1, ... for array jobs; empty for single job)
    arrayIndex := os.Getenv("AWS_BATCH_JOB_ARRAY_INDEX")
    jobID := os.Getenv("AWS_BATCH_JOB_ID")

    // Get input from environment
    inputJSON := os.Getenv("JOB_INPUT")

    // Parse input
    var input JobInput
    json.Unmarshal([]byte(inputJSON), &input)

    // Process based on array index
    result := processItem(arrayIndex, input)

    // Output result to stdout (captured in CloudWatch)
    output, _ := json.MarshalIndent(result, "", "  ")
    fmt.Println(string(output))
}
```

**Terraform Resources:**
- `aws_batch_compute_environment` - Fargate compute (on-demand)
- `aws_batch_job_queue` - Job queue
- `aws_batch_job_definition` - Job definition with container config
- `aws_iam_role` - Service role, execution role

**Test Pattern:** Submit array job (size=2) via Batch API, monitor job status, verify logs

## Additional AWS Batch Capabilities

This demo uses array jobs with size=2. AWS Batch offers more features:

- **Fargate Spot**: Up to 70% cost savings - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/fargate.html)
- **Job Dependencies**: Chain jobs with dependencies - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/job_dependencies.html)
- **Retry Strategies**: Automatic retry with exit code evaluation - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/job_retries.html)
- **Job Timeouts**: Prevent hung jobs - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/job_timeouts.html)
- **Multi-node Parallel Jobs**: Distributed computing - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html)
- **Scheduling Policies**: Fair share scheduling - [Docs](https://docs.aws.amazon.com/batch/latest/userguide/scheduling-policies.html)

## Components

- `apps/batchworker/` - Go application that processes batch jobs with array index support
- `infra/terraform/01-ecr/` - ECR repository for container images
- `infra/terraform/02-app/` - Batch compute environment, job queue, job definition, IAM roles
- `scripts/` - Build, deploy, and test scripts
- `tests/batchtest/` - Test runner to submit array jobs and verify results

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

# Submit a test job manually
cd tests/batchtest
go build -o test-runner .
./test-runner \
    --job-queue="$JOB_QUEUE_ARN" \
    --job-definition="$JOB_DEFINITION_ARN" \
    --array-size=2 \
    --input='{"message": "Hello!", "items": ["item-A", "item-B"]}'
```

## Cleanup

```bash
./scripts/destroy.sh
```

## Related Documentation

- [AWS Batch on Fargate](https://docs.aws.amazon.com/batch/latest/userguide/fargate.html)
- [Array Jobs](https://docs.aws.amazon.com/batch/latest/userguide/array_jobs.html)
- [Job Definitions](https://docs.aws.amazon.com/batch/latest/userguide/job_definitions.html)
