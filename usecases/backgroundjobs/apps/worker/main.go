package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

// JobMessage represents the input JSON structure for a job
type JobMessage struct {
	JobID   string                 `json:"job_id"`
	Action  string                 `json:"action"`
	Payload map[string]interface{} `json:"payload,omitempty"`
}

// JobResult represents the processing result
type JobResult struct {
	JobID   string `json:"job_id"`
	Status  string `json:"status"`
	Message string `json:"message"`
}

func main() {
	log.Println("Background job worker started.")

	// Get SQS queue URL from environment variable
	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		log.Fatal("Error: SQS_QUEUE_URL environment variable is not set.")
	}
	log.Printf("Queue URL: %s\n", queueURL)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigChan
		log.Printf("Received signal %v, shutting down...\n", sig)
		cancel()
	}()

	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS SDK config: %v", err)
	}

	sqsClient := sqs.NewFromConfig(cfg)

	log.Println("Starting to poll for messages...")

	// Main polling loop
	for {
		select {
		case <-ctx.Done():
			log.Println("Shutdown requested, stopping worker...")
			return
		default:
			if err := pollAndProcess(ctx, sqsClient, queueURL); err != nil {
				log.Printf("Error polling messages: %v\n", err)
				// Brief sleep before retrying on error
				time.Sleep(5 * time.Second)
			}
		}
	}
}

func pollAndProcess(ctx context.Context, client *sqs.Client, queueURL string) error {
	// Receive messages with long polling
	result, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            &queueURL,
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     20, // Long polling
		VisibilityTimeout:   300,
	})
	if err != nil {
		return err
	}

	if len(result.Messages) == 0 {
		log.Println("No messages received, continuing to poll...")
		return nil
	}

	log.Printf("Received %d message(s)\n", len(result.Messages))

	for _, msg := range result.Messages {
		if err := processMessage(ctx, client, queueURL, msg); err != nil {
			log.Printf("Error processing message %s: %v\n", *msg.MessageId, err)
			// Don't delete the message on error - it will be retried
			continue
		}
	}

	return nil
}

func processMessage(ctx context.Context, client *sqs.Client, queueURL string, msg types.Message) error {
	messageID := *msg.MessageId
	log.Printf("Processing message: %s\n", messageID)

	// Parse the message body
	var job JobMessage
	if err := json.Unmarshal([]byte(*msg.Body), &job); err != nil {
		log.Printf("Warning: Failed to parse message as JobMessage: %v\n", err)
		// Try to parse as generic JSON for logging
		var generic map[string]interface{}
		if err := json.Unmarshal([]byte(*msg.Body), &generic); err != nil {
			log.Printf("Message body: %s\n", *msg.Body)
		} else {
			job.Payload = generic
		}
	}

	// Process the job (simple example - just log and create result)
	result := JobResult{
		JobID:   job.JobID,
		Status:  "success",
		Message: "Job processed successfully",
	}

	if job.JobID == "" {
		result.JobID = messageID
	}

	if job.Action != "" {
		result.Message = "Processed action: " + job.Action
	}

	// Output the result
	resultBytes, _ := json.MarshalIndent(result, "", "  ")
	log.Printf("--- Job Result ---\n%s\n------------------\n", string(resultBytes))

	// Delete the message from the queue
	_, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      &queueURL,
		ReceiptHandle: msg.ReceiptHandle,
	})
	if err != nil {
		return err
	}

	log.Printf("Message %s deleted successfully\n", messageID)
	return nil
}
