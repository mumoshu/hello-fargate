# Running the Workflow Manually (Testing)

After deploying the infrastructure (either manually or via the E2E script), you can manually trigger the Step Functions state machine using the provided Go test runner.

**(Ensure AWS credentials and region are loaded in your environment)**

## Build Test Runner

1.  Navigate to the test runner directory:
    ```bash
    cd terraform/fargate-scheduled-workflow/test-runner
    # Or adjust path relative to your current directory
    ```

2.  Download Go dependencies (if not already done):
    ```bash
    go mod tidy 
    # or go mod download
    ```

3.  Build the executable:
    ```bash
    go build -o test-runner .
    ```

## Test Modes

The test runner supports three modes of triggering the workflow:

### Mode 1: Direct Step Functions Execution (Default)

Execute the runner with the State Machine ARN obtained from the Terraform output:

```bash
./test-runner --sm-arn="<STATE_MACHINE_ARN_FROM_TERRAFORM_OUTPUT>"
```
*(Replace `<STATE_MACHINE_ARN_FROM_TERRAFORM_OUTPUT>` with the actual ARN)*

**Optional - Provide Input:** Pass initial JSON input to the workflow using the `--input` flag:
```bash
./test-runner --sm-arn="<SM_ARN>" --input='{"startMessage": "Manual trigger via test runner"}'
```

### Mode 2: EventBridge-Triggered Execution

Test the EventBridge integration by sending a custom event that triggers the workflow:

```bash
./test-runner --sm-arn="<SM_ARN>" --mode=eventbridge
```

**With custom input:**
```bash
./test-runner --sm-arn="<SM_ARN>" --mode=eventbridge --input='{"customKey": "customValue"}'
```

**With custom event bus (defaults to "default"):**
```bash
./test-runner --sm-arn="<SM_ARN>" --mode=eventbridge --event-bus="custom-bus-name"
```

### Mode 3: Scheduled EventBridge Trigger

Test the EventBridge scheduled trigger by creating a temporary scheduled rule:

```bash
./test-runner --sm-arn="<SM_ARN>" --mode=scheduled
```

**With custom input:**
```bash
./test-runner --sm-arn="<SM_ARN>" --mode=scheduled --input='{"scheduledData": "test"}'
```

**With custom delay (default is 1 minute):**
```bash
./test-runner --sm-arn="<SM_ARN>" --mode=scheduled --scheduled-delay=2
```

This mode will:
- Create a temporary EventBridge rule with a one-time cron schedule
- Wait for the specified delay (default 1 minute)
- Monitor for the execution triggered by the schedule
- Clean up the temporary rule automatically

## How It Works

### Direct Mode
- Starts a new execution of the state machine directly with the provided input (or default `{}`)
- Prints the execution ARN
- Polls the status of the execution periodically
- Prints the final status (Succeeded, Failed, Aborted, etc.)
- If the execution succeeds, prints the final output JSON

### EventBridge Mode
- Sends a custom event to EventBridge with:
  - Source: `fargate.workflow.test`
  - DetailType: `Test Trigger`
  - Detail: Contains the state machine ARN and test input
- The test EventBridge rule matches this event pattern and triggers the Step Function
- Polls for the newly created execution (identified by recent start time)
- Monitors execution status until completion
- Displays the final output if the execution succeeds

### Scheduled Mode
- Creates a temporary EventBridge rule with a one-time cron expression
- Sets the rule to trigger at current time + delay (default 1 minute)
- Adds the Step Functions state machine as a target with the provided input
- Waits for the scheduled time with a countdown display
- Polls for the execution triggered by the schedule
- Monitors execution status until completion
- Automatically cleans up the temporary rule when done

## What to Expect

- The initial task will run and output a JSON with a `parallelItems` array
- The map state will iterate over each item in `parallelItems`, running a task for each
- The workflow will complete successfully if all tasks succeed
- In EventBridge mode, the state machine input will include `testTriggered: true` and the event details

## Troubleshooting

- Check CloudWatch Logs (log group: `/ecs/fargate-workflow-task`) for detailed task output
- For EventBridge mode, ensure the test rule was created successfully during Terraform deployment
- If the execution doesn't start in EventBridge mode, verify the event pattern matches in the AWS EventBridge console