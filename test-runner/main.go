package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	eventtypes "github.com/aws/aws-sdk-go-v2/service/eventbridge/types"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	"github.com/aws/aws-sdk-go-v2/service/sfn/types"
)

func main() {
	stateMachineArn := flag.String("sm-arn", "", "The ARN of the Step Functions state machine to execute")
	inputJson := flag.String("input", "{}", "JSON input string to pass to the state machine execution")
	testMode := flag.String("mode", "direct", "Test mode: 'direct' for direct Step Functions execution, 'eventbridge' for EventBridge trigger, 'scheduled' for scheduled EventBridge trigger")
	eventBusName := flag.String("event-bus", "default", "EventBridge event bus name (for eventbridge mode)")
	scheduledDelayMinutes := flag.Int("scheduled-delay", 1, "Minutes to wait before scheduled execution (for scheduled mode)")
	flag.Parse()

	if *stateMachineArn == "" {
		fmt.Println("Error: State machine ARN (--sm-arn) is required.")
		flag.Usage()
		os.Exit(1)
	}

	ctx := context.Background()

	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("unable to load SDK config, %v", err)
	}

	var executionArn string

	switch *testMode {
	case "direct":
		executionArn, err = executeDirectly(ctx, cfg, *stateMachineArn, *inputJson)
	case "eventbridge":
		executionArn, err = executeViaEventBridge(ctx, cfg, *stateMachineArn, *inputJson, *eventBusName)
	case "scheduled":
		executionArn, err = executeViaScheduledTrigger(ctx, cfg, *stateMachineArn, *inputJson, *scheduledDelayMinutes)
	default:
		log.Fatalf("Invalid mode: %s. Use 'direct', 'eventbridge', or 'scheduled'", *testMode)
	}

	if err != nil {
		log.Fatalf("Failed to start execution: %v", err)
	}

	// Monitor execution
	if err := monitorExecution(ctx, cfg, executionArn); err != nil {
		log.Fatalf("Failed to monitor execution: %v", err)
	}
}

func executeDirectly(ctx context.Context, cfg aws.Config, stateMachineArn, inputJson string) (string, error) {
	sfnClient := sfn.NewFromConfig(cfg)

	fmt.Printf("Starting direct execution for state machine: %s\n", stateMachineArn)
	startOutput, err := sfnClient.StartExecution(ctx, &sfn.StartExecutionInput{
		StateMachineArn: &stateMachineArn,
		Input:           &inputJson,
	})
	if err != nil {
		return "", fmt.Errorf("failed to start execution: %w", err)
	}

	executionArn := *startOutput.ExecutionArn
	fmt.Printf("Execution started: %s\n", executionArn)
	return executionArn, nil
}

func executeViaEventBridge(ctx context.Context, cfg aws.Config, stateMachineArn, inputJson, eventBusName string) (string, error) {
	ebClient := eventbridge.NewFromConfig(cfg)
	sfnClient := sfn.NewFromConfig(cfg)

	// Parse input JSON to include in event detail
	var inputData map[string]interface{}
	if err := json.Unmarshal([]byte(inputJson), &inputData); err != nil {
		// If input is not valid JSON, wrap it as a string
		inputData = map[string]interface{}{"rawInput": inputJson}
	}

	// Create event detail
	eventDetail := map[string]interface{}{
		"stateMachineArn": stateMachineArn,
		"timestamp":       time.Now().Format(time.RFC3339),
		"testInput":       inputData,
	}

	detailBytes, err := json.Marshal(eventDetail)
	if err != nil {
		return "", fmt.Errorf("failed to marshal event detail: %w", err)
	}

	// Send test event to EventBridge
	fmt.Printf("Sending test event to EventBridge (bus: %s)...\n", eventBusName)
	putEventsInput := &eventbridge.PutEventsInput{
		Entries: []eventtypes.PutEventsRequestEntry{
			{
				Source:       aws.String("fargate.workflow.test"),
				DetailType:   aws.String("Test Trigger"),
				Detail:       aws.String(string(detailBytes)),
				EventBusName: aws.String(eventBusName),
			},
		},
	}

	putEventsOutput, err := ebClient.PutEvents(ctx, putEventsInput)
	if err != nil {
		return "", fmt.Errorf("failed to put event: %w", err)
	}

	if putEventsOutput.FailedEntryCount > 0 && len(putEventsOutput.Entries) > 0 {
		return "", fmt.Errorf("failed to send event: %s", *putEventsOutput.Entries[0].ErrorMessage)
	}

	fmt.Println("Event sent successfully. Waiting for Step Functions execution to start...")

	// Poll for the execution to start
	// We need to list executions and find the one that was just triggered
	time.Sleep(2 * time.Second) // Give EventBridge time to process

	var executionArn string
	maxAttempts := 10
	for i := 0; i < maxAttempts; i++ {
		listOutput, err := sfnClient.ListExecutions(ctx, &sfn.ListExecutionsInput{
			StateMachineArn: &stateMachineArn,
			StatusFilter:    types.ExecutionStatusRunning,
			MaxResults:      int32(10),
		})
		if err != nil {
			return "", fmt.Errorf("failed to list executions: %w", err)
		}

		// Find the most recent execution
		for _, exec := range listOutput.Executions {
			// Check if this execution started recently (within last 30 seconds)
			if time.Since(*exec.StartDate) < 30*time.Second {
				executionArn = *exec.ExecutionArn
				fmt.Printf("Found execution triggered by EventBridge: %s\n", executionArn)
				return executionArn, nil
			}
		}

		if i < maxAttempts-1 {
			fmt.Printf("Waiting for execution to start... (attempt %d/%d)\n", i+1, maxAttempts)
			time.Sleep(3 * time.Second)
		}
	}

	return "", fmt.Errorf("execution not found after %d attempts", maxAttempts)
}

func executeViaScheduledTrigger(ctx context.Context, cfg aws.Config, stateMachineArn, inputJson string, delayMinutes int) (string, error) {
	ebClient := eventbridge.NewFromConfig(cfg)
	sfnClient := sfn.NewFromConfig(cfg)

	// Generate a unique rule name for this test
	timestamp := time.Now().Unix()
	ruleName := fmt.Sprintf("test-scheduled-trigger-%d", timestamp)
	
	// Calculate the schedule time (current time + delay)
	scheduleTime := time.Now().Add(time.Duration(delayMinutes) * time.Minute)
	
	// Create a cron expression for the specific time
	// EventBridge cron format: cron(Minutes Hours Day-of-month Month Day-of-week Year)
	cronExpression := fmt.Sprintf("cron(%d %d %d %d ? %d)", 
		scheduleTime.Minute(),
		scheduleTime.Hour(),
		scheduleTime.Day(),
		int(scheduleTime.Month()),
		scheduleTime.Year())

	fmt.Printf("Creating scheduled rule '%s' to trigger at %s...\n", ruleName, scheduleTime.Format("15:04:05"))
	
	// Create the scheduled rule
	putRuleInput := &eventbridge.PutRuleInput{
		Name:               &ruleName,
		Description:        aws.String(fmt.Sprintf("Temporary test rule to trigger Step Functions at %s", scheduleTime.Format(time.RFC3339))),
		ScheduleExpression: &cronExpression,
		State:              eventtypes.RuleStateEnabled,
	}

	putRuleOutput, err := ebClient.PutRule(ctx, putRuleInput)
	if err != nil {
		return "", fmt.Errorf("failed to create scheduled rule: %w", err)
	}

	fmt.Printf("Created rule with ARN: %s\n", *putRuleOutput.RuleArn)

	// Get the IAM role ARN from the existing scheduled rule
	// We'll reuse the same role that was created for the main scheduled rule

	// List existing targets to find the IAM role
	existingRules, err := ebClient.ListRules(ctx, &eventbridge.ListRulesInput{
		NamePrefix: aws.String("fargate-workflow-schedule-rule"),
	})
	if err != nil || len(existingRules.Rules) == 0 {
		// Clean up the rule we just created
		ebClient.DeleteRule(ctx, &eventbridge.DeleteRuleInput{Name: &ruleName})
		return "", fmt.Errorf("failed to find existing scheduled rule to get IAM role")
	}

	// Get targets from the existing rule to find the IAM role
	existingTargets, err := ebClient.ListTargetsByRule(ctx, &eventbridge.ListTargetsByRuleInput{
		Rule: existingRules.Rules[0].Name,
	})
	if err != nil || len(existingTargets.Targets) == 0 {
		// Clean up the rule we just created
		ebClient.DeleteRule(ctx, &eventbridge.DeleteRuleInput{Name: &ruleName})
		return "", fmt.Errorf("failed to get IAM role from existing rule")
	}

	roleArn := existingTargets.Targets[0].RoleArn

	// Add the Step Functions state machine as a target
	putTargetsInput := &eventbridge.PutTargetsInput{
		Rule: &ruleName,
		Targets: []eventtypes.Target{
			{
				Id:      aws.String("1"),
				Arn:     &stateMachineArn,
				RoleArn: roleArn,
				Input:   &inputJson,
			},
		},
	}

	putTargetsOutput, err := ebClient.PutTargets(ctx, putTargetsInput)
	if err != nil {
		// Clean up the rule we just created
		ebClient.DeleteRule(ctx, &eventbridge.DeleteRuleInput{Name: &ruleName})
		return "", fmt.Errorf("failed to add target to scheduled rule: %w", err)
	}

	if putTargetsOutput.FailedEntryCount > 0 && len(putTargetsOutput.FailedEntries) > 0 {
		// Clean up the rule we just created
		ebClient.DeleteRule(ctx, &eventbridge.DeleteRuleInput{Name: &ruleName})
		return "", fmt.Errorf("failed to add target: %s", *putTargetsOutput.FailedEntries[0].ErrorMessage)
	}

	fmt.Printf("Scheduled rule created successfully. Waiting %d minute(s) for execution...\n", delayMinutes)

	// Ensure cleanup happens
	defer func() {
		fmt.Printf("Cleaning up temporary rule '%s'...\n", ruleName)
		// Remove targets first
		ebClient.RemoveTargets(ctx, &eventbridge.RemoveTargetsInput{
			Rule: &ruleName,
			Ids:  []string{"1"},
		})
		// Then delete the rule
		if _, err := ebClient.DeleteRule(ctx, &eventbridge.DeleteRuleInput{Name: &ruleName}); err != nil {
			fmt.Printf("Warning: Failed to delete temporary rule: %v\n", err)
		} else {
			fmt.Println("Temporary rule cleaned up successfully.")
		}
	}()

	// Wait for the scheduled time plus a buffer
	waitTime := time.Until(scheduleTime) + 30*time.Second
	fmt.Printf("Waiting %v for scheduled execution to trigger...\n", waitTime.Round(time.Second))
	
	// Show countdown
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	
	done := make(chan bool)
	go func() {
		time.Sleep(waitTime)
		done <- true
	}()
	
	countdownLoop:
	for {
		select {
		case <-done:
			fmt.Println("Wait time complete, checking for execution...")
			break countdownLoop
		case <-ticker.C:
			remaining := time.Until(scheduleTime.Add(30 * time.Second))
			if remaining > 0 {
				fmt.Printf("Still waiting... %v remaining\n", remaining.Round(time.Second))
			}
		}
	}

	// Now poll for the execution
	var executionArn string
	maxAttempts := 20 // More attempts since we're looking for a scheduled execution
	for i := 0; i < maxAttempts; i++ {
		listOutput, err := sfnClient.ListExecutions(ctx, &sfn.ListExecutionsInput{
			StateMachineArn: &stateMachineArn,
			MaxResults:      int32(10),
		})
		if err != nil {
			return "", fmt.Errorf("failed to list executions: %w", err)
		}

		// Find the most recent execution that started after our schedule time
		for _, exec := range listOutput.Executions {
			// Check if this execution started after our scheduled time (with some buffer)
			if exec.StartDate.After(scheduleTime.Add(-30*time.Second)) && 
			   exec.StartDate.Before(scheduleTime.Add(2*time.Minute)) {
				executionArn = *exec.ExecutionArn
				fmt.Printf("Found execution triggered by scheduled rule: %s\n", executionArn)
				return executionArn, nil
			}
		}

		if i < maxAttempts-1 {
			fmt.Printf("Checking for scheduled execution... (attempt %d/%d)\n", i+1, maxAttempts)
			time.Sleep(5 * time.Second)
		}
	}

	return "", fmt.Errorf("scheduled execution not found after %d attempts", maxAttempts)
}

func monitorExecution(ctx context.Context, cfg aws.Config, executionArn string) error {
	sfnClient := sfn.NewFromConfig(cfg)

	fmt.Println("Waiting for execution to complete...")

	var lastStatus types.ExecutionStatus
	for {
		descOutput, err := sfnClient.DescribeExecution(ctx, &sfn.DescribeExecutionInput{
			ExecutionArn: &executionArn,
		})
		if err != nil {
			return fmt.Errorf("failed to describe execution: %w", err)
		}

		lastStatus = descOutput.Status
		fmt.Printf("Current status: %s\n", lastStatus)

		if lastStatus == types.ExecutionStatusSucceeded ||
			lastStatus == types.ExecutionStatusFailed ||
			lastStatus == types.ExecutionStatusTimedOut ||
			lastStatus == types.ExecutionStatusAborted {
			break
		}

		time.Sleep(5 * time.Second) // Poll every 5 seconds
	}

	fmt.Printf("Execution finished with status: %s\n", lastStatus)

	// Get final output if succeeded
	if lastStatus == types.ExecutionStatusSucceeded {
		descOutput, err := sfnClient.DescribeExecution(ctx, &sfn.DescribeExecutionInput{
			ExecutionArn: &executionArn,
		})
		if err != nil {
			return fmt.Errorf("failed to describe execution for output: %w", err)
		}

		fmt.Println("\n--- Execution Output --- ")
		var prettyJSON map[string]interface{}
		err = json.Unmarshal([]byte(*descOutput.Output), &prettyJSON)
		if err != nil {
			fmt.Println("Output is not valid JSON, printing as string:")
			fmt.Println(*descOutput.Output)
		} else {
			formattedJSON, _ := json.MarshalIndent(prettyJSON, "", "  ")
			fmt.Println(string(formattedJSON))
		}
		fmt.Println("------------------------")
		return nil
	} else {
		// Optionally retrieve failure details if needed
		fmt.Println("Execution did not succeed. Check the AWS Step Functions console for details.")
		return fmt.Errorf("execution failed with status: %s", lastStatus)
	}
}