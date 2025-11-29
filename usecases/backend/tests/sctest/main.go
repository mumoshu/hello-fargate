package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
)

// TestResponse represents the response from frontend's /api/test endpoint
type TestResponse struct {
	TotalRequests  int            `json:"total_requests"`
	SuccessCount   int            `json:"success_count"`
	FailureCount   int            `json:"failure_count"`
	UniqueBackends int            `json:"unique_backends"`
	Distribution   map[string]int `json:"distribution"`
	Success        bool           `json:"success"`
	Message        string         `json:"message"`
	FrontendID     string         `json:"frontend_id"`
}

func main() {
	clusterArn := flag.String("cluster-arn", "", "ECS cluster ARN")
	frontendService := flag.String("frontend-service", "", "Frontend service name")
	backendService := flag.String("backend-service", "", "Backend service name")
	requestCount := flag.Int("requests", 20, "Number of requests to send to backend")
	timeout := flag.Duration("timeout", 5*time.Minute, "Timeout for the test")
	flag.Parse()

	if *clusterArn == "" || *frontendService == "" || *backendService == "" {
		log.Fatal("Required flags: -cluster-arn, -frontend-service, -backend-service")
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// Load AWS config
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS config: %v", err)
	}

	ecsClient := ecs.NewFromConfig(cfg)
	ec2Client := ec2.NewFromConfig(cfg)

	// Wait for services to be ready
	log.Println("Waiting for ECS services to be ready...")
	if err := waitForServices(ctx, ecsClient, *clusterArn, *backendService, 2, *frontendService, 1); err != nil {
		log.Fatalf("Services not ready: %v", err)
	}

	// Get frontend task's public IP
	log.Println("Getting frontend task public IP...")
	frontendIP, err := getFrontendPublicIP(ctx, ecsClient, ec2Client, *clusterArn, *frontendService)
	if err != nil {
		log.Fatalf("Failed to get frontend IP: %v", err)
	}
	log.Printf("Frontend public IP: %s", frontendIP)

	// Wait for frontend to be healthy
	frontendURL := fmt.Sprintf("http://%s:8080", frontendIP)
	log.Printf("Waiting for frontend to be healthy at %s/health...", frontendURL)
	if err := waitForHealth(ctx, frontendURL+"/health"); err != nil {
		log.Fatalf("Frontend not healthy: %v", err)
	}
	log.Println("Frontend is healthy!")

	// Run the test
	testURL := fmt.Sprintf("%s/api/test?requests=%d", frontendURL, *requestCount)
	log.Printf("Running Service Connect test: %s", testURL)

	result, err := runTest(ctx, testURL)
	if err != nil {
		log.Fatalf("Test failed: %v", err)
	}

	// Print results
	fmt.Println("\n--- Service Connect Test Results ---")
	fmt.Printf("Total Requests: %d\n", result.TotalRequests)
	fmt.Printf("Successful: %d\n", result.SuccessCount)
	fmt.Printf("Failed: %d\n", result.FailureCount)
	fmt.Printf("Unique Backends: %d\n", result.UniqueBackends)
	fmt.Println("\nDistribution:")
	for backendID, count := range result.Distribution {
		pct := float64(count) / float64(result.TotalRequests) * 100
		fmt.Printf("  %s: %d requests (%.1f%%)\n", backendID, count, pct)
	}
	fmt.Printf("\nFrontend ID: %s\n", result.FrontendID)
	fmt.Printf("Result: %s\n", result.Message)
	fmt.Println("------------------------------------")

	if !result.Success {
		log.Fatal("Test FAILED: Expected at least 2 unique backends")
	}

	log.Println("Test PASSED: Service Connect load balancing verified!")
}

func waitForServices(ctx context.Context, client *ecs.Client, cluster, backendSvc string, backendCount int, frontendSvc string, frontendCount int) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Check backend service
		backendResp, err := client.DescribeServices(ctx, &ecs.DescribeServicesInput{
			Cluster:  &cluster,
			Services: []string{backendSvc},
		})
		if err != nil {
			return fmt.Errorf("failed to describe backend service: %w", err)
		}
		if len(backendResp.Services) == 0 {
			return fmt.Errorf("backend service not found")
		}
		backendRunning := backendResp.Services[0].RunningCount

		// Check frontend service
		frontendResp, err := client.DescribeServices(ctx, &ecs.DescribeServicesInput{
			Cluster:  &cluster,
			Services: []string{frontendSvc},
		})
		if err != nil {
			return fmt.Errorf("failed to describe frontend service: %w", err)
		}
		if len(frontendResp.Services) == 0 {
			return fmt.Errorf("frontend service not found")
		}
		frontendRunning := frontendResp.Services[0].RunningCount

		log.Printf("Service status - Backend: %d/%d, Frontend: %d/%d",
			backendRunning, backendCount, frontendRunning, frontendCount)

		if backendRunning >= int32(backendCount) && frontendRunning >= int32(frontendCount) {
			return nil
		}

		time.Sleep(5 * time.Second)
	}
}

func getFrontendPublicIP(ctx context.Context, ecsClient *ecs.Client, ec2Client *ec2.Client, cluster, serviceName string) (string, error) {
	// List tasks for the frontend service
	listResp, err := ecsClient.ListTasks(ctx, &ecs.ListTasksInput{
		Cluster:     &cluster,
		ServiceName: &serviceName,
	})
	if err != nil {
		return "", fmt.Errorf("failed to list tasks: %w", err)
	}
	if len(listResp.TaskArns) == 0 {
		return "", fmt.Errorf("no tasks found for service")
	}

	log.Printf("Found %d task(s) for service %s", len(listResp.TaskArns), serviceName)

	// Describe the first task to get its network details
	descResp, err := ecsClient.DescribeTasks(ctx, &ecs.DescribeTasksInput{
		Cluster: &cluster,
		Tasks:   []string{listResp.TaskArns[0]},
	})
	if err != nil {
		return "", fmt.Errorf("failed to describe task: %w", err)
	}
	if len(descResp.Tasks) == 0 {
		return "", fmt.Errorf("task not found")
	}

	task := descResp.Tasks[0]

	// Log task details for debugging
	log.Printf("Task ARN: %s", *task.TaskArn)
	log.Printf("Task Status: %s", *task.LastStatus)
	if task.StoppedReason != nil {
		log.Printf("Stopped Reason: %s", *task.StoppedReason)
	}

	// Log all attachments for debugging
	log.Printf("Task has %d attachment(s)", len(task.Attachments))
	var eniID string
	for i, attachment := range task.Attachments {
		log.Printf("  Attachment[%d]: Type=%s, Status=%s", i, *attachment.Type, *attachment.Status)
		for _, detail := range attachment.Details {
			if detail.Name != nil && detail.Value != nil {
				log.Printf("    %s = %s", *detail.Name, *detail.Value)
				// Capture ENI ID for fallback lookup
				if *detail.Name == "networkInterfaceId" {
					eniID = *detail.Value
				}
			}
		}
	}

	// Look for public IP in attachments first
	for _, attachment := range task.Attachments {
		if *attachment.Type == "ElasticNetworkInterface" {
			for _, detail := range attachment.Details {
				if detail.Name != nil && *detail.Name == "publicIPv4Address" && detail.Value != nil {
					return *detail.Value, nil
				}
			}
		}
	}

	// Check if we need to wait for ENI attachment
	for _, attachment := range task.Attachments {
		if *attachment.Type == "ElasticNetworkInterface" {
			if *attachment.Status != "ATTACHED" {
				return "", fmt.Errorf("ENI not yet attached (status: %s), need to wait", *attachment.Status)
			}
		}
	}

	// Fallback: Query EC2 API directly for the ENI's public IP
	// ECS task attachment details sometimes don't include publicIPv4Address even when assigned
	if eniID != "" {
		log.Printf("Public IP not in ECS task details, querying EC2 API for ENI %s...", eniID)
		eniResp, err := ec2Client.DescribeNetworkInterfaces(ctx, &ec2.DescribeNetworkInterfacesInput{
			NetworkInterfaceIds: []string{eniID},
		})
		if err != nil {
			return "", fmt.Errorf("failed to describe ENI %s: %w", eniID, err)
		}
		if len(eniResp.NetworkInterfaces) > 0 {
			eni := eniResp.NetworkInterfaces[0]
			if eni.Association != nil && eni.Association.PublicIp != nil {
				log.Printf("Found public IP via EC2 API: %s", *eni.Association.PublicIp)
				return *eni.Association.PublicIp, nil
			}
		}
	}

	return "", fmt.Errorf("no public IP found for task - check if assign_public_ip is enabled in network configuration")
}

// getPublicIPFromENI queries EC2 API to get public IP for an ENI
func getPublicIPFromENI(ctx context.Context, ec2Client *ec2.Client, eniID string) (string, error) {
	resp, err := ec2Client.DescribeNetworkInterfaces(ctx, &ec2.DescribeNetworkInterfacesInput{
		NetworkInterfaceIds: []string{eniID},
	})
	if err != nil {
		return "", fmt.Errorf("failed to describe ENI: %w", err)
	}
	if len(resp.NetworkInterfaces) == 0 {
		return "", fmt.Errorf("ENI not found")
	}

	eni := resp.NetworkInterfaces[0]
	if eni.Association != nil && eni.Association.PublicIp != nil {
		return aws.ToString(eni.Association.PublicIp), nil
	}

	return "", fmt.Errorf("no public IP associated with ENI")
}

func waitForHealth(ctx context.Context, healthURL string) error {
	client := &http.Client{Timeout: 5 * time.Second}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		resp, err := client.Get(healthURL)
		if err == nil && resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			return nil
		}
		if resp != nil {
			resp.Body.Close()
		}

		log.Printf("Waiting for health check... (%v)", err)
		time.Sleep(5 * time.Second)
	}
}

func runTest(ctx context.Context, testURL string) (*TestResponse, error) {
	client := &http.Client{Timeout: 60 * time.Second}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, testURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var result TestResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &result, nil
}
