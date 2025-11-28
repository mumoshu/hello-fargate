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
	"github.com/aws/aws-sdk-go-v2/service/ecs/types"
)

func main() {
	clusterArn := flag.String("cluster-arn", "", "The ARN of the ECS cluster")
	taskDefinitionArn := flag.String("task-definition-arn", "", "The ARN of the task definition")
	subnetIDs := flag.String("subnet-ids", "", "Comma-separated list of subnet IDs")
	securityGroupID := flag.String("security-group-id", "", "The security group ID")
	containerName := flag.String("container-name", "", "The name of the container")
	inputJSON := flag.String("input", "{}", "JSON input to pass to the task")
	flag.Parse()

	if *clusterArn == "" || *taskDefinitionArn == "" || *subnetIDs == "" || *securityGroupID == "" {
		fmt.Println("Error: All flags are required: --cluster-arn, --task-definition-arn, --subnet-ids, --security-group-id")
		flag.Usage()
		os.Exit(1)
	}

	ctx := context.Background()

	// Load AWS configuration
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS SDK config: %v", err)
	}

	ecsClient := ecs.NewFromConfig(cfg)

	// Parse subnet IDs
	subnets := strings.Split(*subnetIDs, ",")
	for i := range subnets {
		subnets[i] = strings.TrimSpace(subnets[i])
	}

	// Run the task
	fmt.Printf("Running ECS task...\n")
	fmt.Printf("  Cluster: %s\n", *clusterArn)
	fmt.Printf("  Task Definition: %s\n", *taskDefinitionArn)
	fmt.Printf("  Subnets: %v\n", subnets)
	fmt.Printf("  Security Group: %s\n", *securityGroupID)
	fmt.Printf("  Input: %s\n", *inputJSON)

	runTaskInput := &ecs.RunTaskInput{
		Cluster:        clusterArn,
		TaskDefinition: taskDefinitionArn,
		LaunchType:     types.LaunchTypeFargate,
		NetworkConfiguration: &types.NetworkConfiguration{
			AwsvpcConfiguration: &types.AwsVpcConfiguration{
				Subnets:        subnets,
				SecurityGroups: []string{*securityGroupID},
				AssignPublicIp: types.AssignPublicIpEnabled,
			},
		},
		Overrides: &types.TaskOverride{
			ContainerOverrides: []types.ContainerOverride{
				{
					Name: containerName,
					Environment: []types.KeyValuePair{
						{
							Name:  aws.String("TASK_INPUT"),
							Value: inputJSON,
						},
					},
				},
			},
		},
	}

	runTaskOutput, err := ecsClient.RunTask(ctx, runTaskInput)
	if err != nil {
		log.Fatalf("Failed to run task: %v", err)
	}

	if len(runTaskOutput.Failures) > 0 {
		for _, failure := range runTaskOutput.Failures {
			fmt.Printf("Task failure: %s - %s\n", *failure.Arn, *failure.Reason)
		}
		log.Fatalf("Failed to start task")
	}

	if len(runTaskOutput.Tasks) == 0 {
		log.Fatalf("No tasks were started")
	}

	taskArn := *runTaskOutput.Tasks[0].TaskArn
	fmt.Printf("Task started: %s\n", taskArn)

	// Wait for task to complete
	fmt.Println("Waiting for task to complete...")
	var lastStatus string
	var stoppedReason string
	var exitCode int32

	for {
		describeTasksOutput, err := ecsClient.DescribeTasks(ctx, &ecs.DescribeTasksInput{
			Cluster: clusterArn,
			Tasks:   []string{taskArn},
		})
		if err != nil {
			log.Fatalf("Failed to describe task: %v", err)
		}

		if len(describeTasksOutput.Tasks) == 0 {
			log.Fatalf("Task not found")
		}

		task := describeTasksOutput.Tasks[0]
		lastStatus = *task.LastStatus
		fmt.Printf("Task status: %s\n", lastStatus)

		if lastStatus == "STOPPED" {
			if task.StoppedReason != nil {
				stoppedReason = *task.StoppedReason
			}
			// Get exit code from container
			for _, container := range task.Containers {
				if container.ExitCode != nil {
					exitCode = *container.ExitCode
				}
			}
			break
		}

		time.Sleep(5 * time.Second)
	}

	fmt.Printf("\nTask completed with status: %s\n", lastStatus)
	if stoppedReason != "" {
		fmt.Printf("Stopped reason: %s\n", stoppedReason)
	}
	fmt.Printf("Exit code: %d\n", exitCode)

	// Fetch CloudWatch logs
	fmt.Println("\n--- CloudWatch Logs ---")
	fetchLogs(ctx, cfg, taskArn)
	fmt.Println("-----------------------")

	if exitCode != 0 {
		os.Exit(int(exitCode))
	}
}

func fetchLogs(ctx context.Context, cfg aws.Config, taskArn string) {
	logsClient := cloudwatchlogs.NewFromConfig(cfg)

	// Extract task ID from ARN
	parts := strings.Split(taskArn, "/")
	taskID := parts[len(parts)-1]

	logGroupName := "/ecs/hello-fargate-oneoff-task"
	logStreamPrefix := fmt.Sprintf("ecs/hello-fargate-oneoff-app-container/%s", taskID)

	// List log streams
	listStreamsOutput, err := logsClient.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
		LogGroupName:        &logGroupName,
		LogStreamNamePrefix: &logStreamPrefix,
	})
	if err != nil {
		fmt.Printf("Warning: Could not list log streams: %v\n", err)
		return
	}

	if len(listStreamsOutput.LogStreams) == 0 {
		fmt.Println("No log streams found")
		return
	}

	// Get log events
	logStreamName := *listStreamsOutput.LogStreams[0].LogStreamName
	getLogsOutput, err := logsClient.GetLogEvents(ctx, &cloudwatchlogs.GetLogEventsInput{
		LogGroupName:  &logGroupName,
		LogStreamName: &logStreamName,
		StartFromHead: aws.Bool(true),
	})
	if err != nil {
		fmt.Printf("Warning: Could not get log events: %v\n", err)
		return
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
