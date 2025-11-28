package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/google/uuid"
)

// JobMessage represents the message structure sent to SQS
type JobMessage struct {
	JobID   string                 `json:"job_id"`
	Action  string                 `json:"action"`
	Payload map[string]interface{} `json:"payload,omitempty"`
}

func main() {
	queueURL := flag.String("queue-url", "", "The URL of the SQS queue")
	logGroupName := flag.String("log-group", "", "The CloudWatch log group name")
	clusterArn := flag.String("cluster-arn", "", "The ARN of the ECS cluster")
	serviceName := flag.String("service-name", "", "The name of the ECS service")
	timeout := flag.Duration("timeout", 120*time.Second, "Timeout for waiting for message processing")
	flag.Parse()

	if *queueURL == "" || *logGroupName == "" || *clusterArn == "" || *serviceName == "" {
		fmt.Println("Error: All flags are required: --queue-url, --log-group, --cluster-arn, --service-name")
		flag.Usage()
		os.Exit(1)
	}

	ctx := context.Background()

	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS SDK config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(cfg)
	ecsClient := ecs.NewFromConfig(cfg)

	// Verify ECS service is running
	fmt.Println("Verifying ECS service is running...")
	if err := waitForService(ctx, ecsClient, *clusterArn, *serviceName, 60*time.Second); err != nil {
		log.Fatalf("Service not ready: %v", err)
	}
	fmt.Println("ECS service is running with desired tasks.")

	// Generate a unique job ID to track this specific message
	jobID := uuid.New().String()
	fmt.Printf("Generated job ID: %s\n", jobID)

	// Create test message
	testMessage := JobMessage{
		JobID:  jobID,
		Action: "test",
		Payload: map[string]interface{}{
			"message":   "Hello from E2E test!",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		},
	}

	messageBody, err := json.Marshal(testMessage)
	if err != nil {
		log.Fatalf("Failed to marshal message: %v", err)
	}

	// Send message to SQS
	fmt.Printf("Sending message to SQS queue: %s\n", *queueURL)
	fmt.Printf("Message body: %s\n", string(messageBody))

	sendOutput, err := sqsClient.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    queueURL,
		MessageBody: aws.String(string(messageBody)),
	})
	if err != nil {
		log.Fatalf("Failed to send message: %v", err)
	}

	fmt.Printf("Message sent successfully. Message ID: %s\n", *sendOutput.MessageId)

	// Wait for the message to be processed by checking CloudWatch logs
	fmt.Printf("Waiting for message to be processed (timeout: %v)...\n", *timeout)

	startTime := time.Now()
	processed := false
	checkInterval := 5 * time.Second

	for time.Since(startTime) < *timeout {
		if checkJobInLogs(ctx, cfg, *logGroupName, jobID, startTime) {
			processed = true
			break
		}
		fmt.Printf("  Message not yet processed, waiting %v...\n", checkInterval)
		time.Sleep(checkInterval)
	}

	if !processed {
		fmt.Println("\n--- CloudWatch Logs (last 50 entries) ---")
		fetchRecentLogs(ctx, cfg, *logGroupName, 50)
		fmt.Println("------------------------------------------")
		log.Fatalf("Timeout: Message was not processed within %v", *timeout)
	}

	fmt.Printf("\nMessage processed successfully!\n")
	fmt.Println("\n--- Relevant CloudWatch Logs ---")
	fetchRecentLogs(ctx, cfg, *logGroupName, 20)
	fmt.Println("--------------------------------")
}

func waitForService(ctx context.Context, client *ecs.Client, clusterArn, serviceName string, timeout time.Duration) error {
	startTime := time.Now()

	for time.Since(startTime) < timeout {
		output, err := client.DescribeServices(ctx, &ecs.DescribeServicesInput{
			Cluster:  &clusterArn,
			Services: []string{serviceName},
		})
		if err != nil {
			return fmt.Errorf("failed to describe service: %w", err)
		}

		if len(output.Services) == 0 {
			return fmt.Errorf("service not found")
		}

		service := output.Services[0]
		fmt.Printf("  Service status: %s, Running count: %d, Desired count: %d\n",
			*service.Status, service.RunningCount, service.DesiredCount)

		if service.RunningCount > 0 && *service.Status == "ACTIVE" {
			return nil
		}

		time.Sleep(5 * time.Second)
	}

	return fmt.Errorf("timeout waiting for service to have running tasks")
}

func checkJobInLogs(ctx context.Context, cfg aws.Config, logGroupName, jobID string, since time.Time) bool {
	logsClient := cloudwatchlogs.NewFromConfig(cfg)

	// Query logs for our specific job ID
	startTime := since.Add(-1 * time.Minute).UnixMilli() // Give some buffer

	// List all log streams and check for our job ID
	var nextToken *string
	for {
		listOutput, err := logsClient.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
			LogGroupName: &logGroupName,
			OrderBy:      "LastEventTime",
			Descending:   aws.Bool(true),
			NextToken:    nextToken,
			Limit:        aws.Int32(10),
		})
		if err != nil {
			fmt.Printf("Warning: Could not list log streams: %v\n", err)
			return false
		}

		for _, stream := range listOutput.LogStreams {
			events, err := logsClient.GetLogEvents(ctx, &cloudwatchlogs.GetLogEventsInput{
				LogGroupName:  &logGroupName,
				LogStreamName: stream.LogStreamName,
				StartTime:     &startTime,
				StartFromHead: aws.Bool(false),
			})
			if err != nil {
				continue
			}

			// Check events for our job ID, and look for success status nearby
			// The log format has the JSON pretty-printed across multiple lines
			foundJobID := false
			for _, event := range events.Events {
				msg := *event.Message
				if strings.Contains(msg, jobID) {
					foundJobID = true
				}
				// If we found our job ID and see success status, we're done
				if foundJobID && strings.Contains(msg, `"status": "success"`) {
					return true
				}
				// Reset if we see a different job starting
				if strings.Contains(msg, "Processing message:") && !strings.Contains(msg, jobID) {
					foundJobID = false
				}
			}
		}

		if listOutput.NextToken == nil {
			break
		}
		nextToken = listOutput.NextToken
	}

	return false
}

func fetchRecentLogs(ctx context.Context, cfg aws.Config, logGroupName string, limit int) {
	logsClient := cloudwatchlogs.NewFromConfig(cfg)

	// List recent log streams
	listStreamsOutput, err := logsClient.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
		LogGroupName: &logGroupName,
		OrderBy:      "LastEventTime",
		Descending:   aws.Bool(true),
		Limit:        aws.Int32(5),
	})
	if err != nil {
		fmt.Printf("Warning: Could not list log streams: %v\n", err)
		return
	}

	if len(listStreamsOutput.LogStreams) == 0 {
		fmt.Println("No log streams found")
		return
	}

	eventCount := 0
	for _, stream := range listStreamsOutput.LogStreams {
		if eventCount >= limit {
			break
		}

		getLogsOutput, err := logsClient.GetLogEvents(ctx, &cloudwatchlogs.GetLogEventsInput{
			LogGroupName:  &logGroupName,
			LogStreamName: stream.LogStreamName,
			StartFromHead: aws.Bool(false),
			Limit:         aws.Int32(int32(limit - eventCount)),
		})
		if err != nil {
			continue
		}

		for _, event := range getLogsOutput.Events {
			// Try to pretty print JSON output
			var prettyJSON map[string]interface{}
			if err := json.Unmarshal([]byte(*event.Message), &prettyJSON); err == nil {
				formattedJSON, _ := json.MarshalIndent(prettyJSON, "", "  ")
				fmt.Println(string(formattedJSON))
			} else {
				fmt.Println(*event.Message)
			}
			eventCount++
		}
	}
}
