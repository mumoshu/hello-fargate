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
	"github.com/aws/aws-sdk-go-v2/service/batch"
	batchtypes "github.com/aws/aws-sdk-go-v2/service/batch/types"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	cwltypes "github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"
)

func main() {
	jobQueue := flag.String("job-queue", "", "The ARN of the Batch job queue")
	jobDefinition := flag.String("job-definition", "", "The ARN of the job definition")
	inputJSON := flag.String("input", "{}", "JSON input to pass to the job")
	arraySize := flag.Int("array-size", 2, "Array job size (number of parallel jobs)")
	logGroupName := flag.String("log-group", "/aws/batch/hello-fargate-batchjobs", "CloudWatch log group name")
	timeout := flag.Duration("timeout", 5*time.Minute, "Timeout for job completion")
	flag.Parse()

	if *jobQueue == "" || *jobDefinition == "" {
		fmt.Println("Error: Required flags: --job-queue, --job-definition")
		flag.Usage()
		os.Exit(1)
	}

	ctx := context.Background()

	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS SDK config: %v", err)
	}

	batchClient := batch.NewFromConfig(cfg)

	// Generate unique job name
	jobName := fmt.Sprintf("e2e-test-job-%d", time.Now().Unix())

	fmt.Printf("Submitting AWS Batch array job...\n")
	fmt.Printf("  Job Queue: %s\n", *jobQueue)
	fmt.Printf("  Job Definition: %s\n", *jobDefinition)
	fmt.Printf("  Array Size: %d\n", *arraySize)
	fmt.Printf("  Input: %s\n", *inputJSON)

	submitJobInput := &batch.SubmitJobInput{
		JobName:       &jobName,
		JobQueue:      jobQueue,
		JobDefinition: jobDefinition,
		ArrayProperties: &batchtypes.ArrayProperties{
			Size: aws.Int32(int32(*arraySize)),
		},
		ContainerOverrides: &batchtypes.ContainerOverrides{
			Environment: []batchtypes.KeyValuePair{
				{
					Name:  aws.String("JOB_INPUT"),
					Value: inputJSON,
				},
			},
		},
	}

	submitOutput, err := batchClient.SubmitJob(ctx, submitJobInput)
	if err != nil {
		log.Fatalf("Failed to submit job: %v", err)
	}

	jobID := *submitOutput.JobId
	fmt.Printf("Job submitted: %s (ID: %s)\n", jobName, jobID)

	// Wait for job to complete
	fmt.Println("Waiting for array job to complete...")
	startTime := time.Now()

	var finalStatus batchtypes.JobStatus
	var statusReason string

	for {
		if time.Since(startTime) > *timeout {
			fmt.Println("\n=== TIMEOUT DIAGNOSTICS ===")
			printDiagnostics(ctx, batchClient, jobID, *jobQueue)
			fmt.Println("===========================\n")
			log.Fatalf("Timeout waiting for job to complete (waited %v)", *timeout)
		}

		describeOutput, err := batchClient.DescribeJobs(ctx, &batch.DescribeJobsInput{
			Jobs: []string{jobID},
		})
		if err != nil {
			log.Fatalf("Failed to describe job: %v", err)
		}

		if len(describeOutput.Jobs) == 0 {
			log.Fatalf("Job not found: %s", jobID)
		}

		job := describeOutput.Jobs[0]
		finalStatus = job.Status
		if job.StatusReason != nil {
			statusReason = *job.StatusReason
		}

		// Print array job progress
		if job.ArrayProperties != nil {
			summary := job.ArrayProperties.StatusSummary
			fmt.Printf("Job status: %s (PENDING:%d, RUNNABLE:%d, RUNNING:%d, SUCCEEDED:%d, FAILED:%d)\n",
				finalStatus,
				getStatusCount(summary, "PENDING"),
				getStatusCount(summary, "RUNNABLE"),
				getStatusCount(summary, "RUNNING"),
				getStatusCount(summary, "SUCCEEDED"),
				getStatusCount(summary, "FAILED"),
			)
		} else {
			fmt.Printf("Job status: %s\n", finalStatus)
		}

		// Check if job is in terminal state
		if finalStatus == batchtypes.JobStatusSucceeded ||
			finalStatus == batchtypes.JobStatusFailed {
			break
		}

		time.Sleep(5 * time.Second)
	}

	fmt.Printf("\nJob completed with status: %s\n", finalStatus)
	if statusReason != "" {
		fmt.Printf("Status reason: %s\n", statusReason)
	}

	// Fetch CloudWatch logs for all array job children
	fmt.Println("\n--- CloudWatch Logs ---")
	fetchLogs(ctx, cfg, *logGroupName, jobID, *arraySize)
	fmt.Println("-----------------------")

	if finalStatus != batchtypes.JobStatusSucceeded {
		fmt.Printf("Job failed with status: %s\n", finalStatus)
		os.Exit(1)
	}

	fmt.Println("All array jobs completed successfully!")
}

func getStatusCount(summary map[string]int32, status string) int32 {
	if summary == nil {
		return 0
	}
	return summary[status]
}

func fetchLogs(ctx context.Context, cfg aws.Config, logGroupName, jobID string, arraySize int) {
	logsClient := cloudwatchlogs.NewFromConfig(cfg)

	// For array jobs, logs are organized by array index
	// Log stream pattern: batch/<job-definition-name>/default/<job-id>:<array-index>
	// or: batch/<container-name>/<job-id>

	// List all log streams that might contain our job's logs
	listStreamsOutput, err := logsClient.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
		LogGroupName: &logGroupName,
		OrderBy:      "LastEventTime",
		Descending:   aws.Bool(true),
		Limit:        aws.Int32(50),
	})
	if err != nil {
		fmt.Printf("Warning: Could not list log streams: %v\n", err)
		return
	}

	if len(listStreamsOutput.LogStreams) == 0 {
		fmt.Println("No log streams found")
		return
	}

	// Find log streams related to our job
	var relevantStreams []string
	for _, stream := range listStreamsOutput.LogStreams {
		streamName := *stream.LogStreamName
		// Check if this stream is related to our job (contains job ID or array index pattern)
		if strings.Contains(streamName, jobID) || isRecentStream(stream) {
			relevantStreams = append(relevantStreams, streamName)
		}
	}

	// If no streams match job ID, take the most recent ones (likely our job's logs)
	if len(relevantStreams) == 0 && len(listStreamsOutput.LogStreams) > 0 {
		for i := 0; i < min(arraySize, len(listStreamsOutput.LogStreams)); i++ {
			relevantStreams = append(relevantStreams, *listStreamsOutput.LogStreams[i].LogStreamName)
		}
	}

	// Fetch logs from each relevant stream
	for _, streamName := range relevantStreams {
		fmt.Printf("\n[Log Stream: %s]\n", streamName)

		getLogsOutput, err := logsClient.GetLogEvents(ctx, &cloudwatchlogs.GetLogEventsInput{
			LogGroupName:  &logGroupName,
			LogStreamName: &streamName,
			StartFromHead: aws.Bool(true),
			Limit:         aws.Int32(100),
		})
		if err != nil {
			fmt.Printf("Warning: Could not get log events: %v\n", err)
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
		}
	}
}

func isRecentStream(stream cwltypes.LogStream) bool {
	if stream.LastEventTimestamp == nil {
		return false
	}
	// Consider streams from the last 5 minutes as recent
	lastEvent := time.UnixMilli(*stream.LastEventTimestamp)
	return time.Since(lastEvent) < 5*time.Minute
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// printDiagnostics fetches and prints status/statusReason for job, job queue, and compute environment
// to help debug issues like jobs stuck in RUNNABLE state
func printDiagnostics(ctx context.Context, batchClient *batch.Client, jobID, jobQueueARN string) {
	// 1. Job details
	fmt.Println("\n[Job Details]")
	describeJobsOutput, err := batchClient.DescribeJobs(ctx, &batch.DescribeJobsInput{
		Jobs: []string{jobID},
	})
	if err != nil {
		fmt.Printf("  Error describing job: %v\n", err)
	} else if len(describeJobsOutput.Jobs) > 0 {
		job := describeJobsOutput.Jobs[0]
		fmt.Printf("  Job ID: %s\n", jobID)
		fmt.Printf("  Status: %s\n", job.Status)
		if job.StatusReason != nil && *job.StatusReason != "" {
			fmt.Printf("  StatusReason: %s\n", *job.StatusReason)
		} else {
			fmt.Println("  StatusReason: (none)")
		}
		// Print child job status if array job
		if job.ArrayProperties != nil && job.ArrayProperties.Size != nil {
			fmt.Printf("  Array Size: %d\n", *job.ArrayProperties.Size)
		}
	}

	// 2. Job Queue details
	fmt.Println("\n[Job Queue Details]")
	describeQueuesOutput, err := batchClient.DescribeJobQueues(ctx, &batch.DescribeJobQueuesInput{
		JobQueues: []string{jobQueueARN},
	})
	if err != nil {
		fmt.Printf("  Error describing job queue: %v\n", err)
	} else if len(describeQueuesOutput.JobQueues) > 0 {
		queue := describeQueuesOutput.JobQueues[0]
		fmt.Printf("  Queue Name: %s\n", *queue.JobQueueName)
		fmt.Printf("  State: %s\n", queue.State)
		fmt.Printf("  Status: %s\n", queue.Status)
		if queue.StatusReason != nil && *queue.StatusReason != "" {
			fmt.Printf("  StatusReason: %s\n", *queue.StatusReason)
		}

		// 3. Compute Environment details (from job queue)
		for _, ceOrder := range queue.ComputeEnvironmentOrder {
			fmt.Println("\n[Compute Environment Details]")
			describeCEOutput, err := batchClient.DescribeComputeEnvironments(ctx, &batch.DescribeComputeEnvironmentsInput{
				ComputeEnvironments: []string{*ceOrder.ComputeEnvironment},
			})
			if err != nil {
				fmt.Printf("  Error describing compute environment: %v\n", err)
				continue
			}
			if len(describeCEOutput.ComputeEnvironments) > 0 {
				ce := describeCEOutput.ComputeEnvironments[0]
				fmt.Printf("  CE Name: %s\n", *ce.ComputeEnvironmentName)
				fmt.Printf("  State: %s\n", ce.State)
				fmt.Printf("  Status: %s\n", ce.Status)
				if ce.StatusReason != nil && *ce.StatusReason != "" {
					fmt.Printf("  StatusReason: %s\n", *ce.StatusReason)
				}
				if ce.ComputeResources != nil {
					fmt.Printf("  Type: %s\n", ce.ComputeResources.Type)
					fmt.Printf("  MaxvCpus: %d\n", *ce.ComputeResources.MaxvCpus)
				}
			}
		}
	}

	// 4. Check child jobs for array jobs
	fmt.Println("\n[Array Child Jobs (first 5)]")
	listJobsOutput, err := batchClient.ListJobs(ctx, &batch.ListJobsInput{
		ArrayJobId: &jobID,
		MaxResults: aws.Int32(5),
	})
	if err != nil {
		fmt.Printf("  Error listing child jobs: %v\n", err)
	} else if len(listJobsOutput.JobSummaryList) > 0 {
		for _, jobSummary := range listJobsOutput.JobSummaryList {
			fmt.Printf("  Child Job: %s - Status: %s", *jobSummary.JobId, jobSummary.Status)
			if jobSummary.StatusReason != nil && *jobSummary.StatusReason != "" {
				fmt.Printf(" - Reason: %s", *jobSummary.StatusReason)
			}
			fmt.Println()
		}
	} else {
		fmt.Println("  No child jobs found")
	}
}
