package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
)

// Input from Step Functions (original execution input or map item)
// We expect the raw JSON string in TASK_INPUT env var
type TaskInput map[string]interface{} // Use a generic map for flexibility

// Output structure for the Initial Step
type InitialStepOutput struct {
	Message       string        `json:"message"`
	ParallelItems []interface{} `json:"parallelItems"`
}

// Output structure for Parallel Tasks
type ParallelTaskOutput struct {
	ResultMessage string `json:"resultMessage"`
}

func main() {
	log.Println("Fargate task started with SFN Task Token integration.")
	ctx := context.Background()

	// --- Get Task Token and Input ---
	taskToken := os.Getenv("AWS_STEP_FUNCTIONS_TASK_TOKEN")
	if taskToken == "" {
		log.Fatal("Error: AWS_STEP_FUNCTIONS_TASK_TOKEN environment variable not set.")
	}

	inputJsonString := os.Getenv("TASK_INPUT")
	if inputJsonString == "" {
		sendFailure(ctx, taskToken, "MissingInput", "TASK_INPUT environment variable not set.")
		log.Fatal("Error: TASK_INPUT environment variable not set.")
	}

	var taskInput TaskInput
	err := json.Unmarshal([]byte(inputJsonString), &taskInput)
	if err != nil {
		sendFailure(ctx, taskToken, "InvalidInputJSON", fmt.Sprintf("Failed to unmarshal TASK_INPUT: %v", err))
		log.Fatalf("Error unmarshalling TASK_INPUT: %v\n", err)
	}
	log.Printf("Received input: %+v\n", taskInput)

	// --- Task Logic ---
	// Determine if this is the initial step or a parallel step based on input
	// A simple heuristic: if input contains a specific key added by the parallel step item, it's parallel.
	// In our TF definition, the parallel item is the whole object {"task_input": "..."}, so check for "task_input"
	var outputJsonBytes []byte
	if _, isParallelTask := taskInput["task_input"]; isParallelTask {
		// Logic for Parallel Task
		log.Println("Running as a parallel task.")
		// Process the item (taskInput contains the item)
		resultMsg := fmt.Sprintf("Successfully processed parallel item: %v", taskInput)
		output := ParallelTaskOutput{ResultMessage: resultMsg}
		outputJsonBytes, err = json.Marshal(output)
		if err != nil {
			sendFailure(ctx, taskToken, "OutputMarshalError", fmt.Sprintf("Failed to marshal parallel task output: %v", err))
			log.Fatalf("Error marshalling parallel task output: %v\n", err)
		}
	} else {
		// Logic for Initial Step
		log.Println("Running as the initial task.")
		// Generate dummy items for the map state
		dummyItems := []interface{}{
			map[string]string{"task_input": "item_A"},
			map[string]string{"task_input": "item_B"},
			map[string]string{"task_input": "item_C"},
		}
		output := InitialStepOutput{
			Message:       "Output from Initial Step",
			ParallelItems: dummyItems,
		}
		outputJsonBytes, err = json.Marshal(output)
		if err != nil {
			sendFailure(ctx, taskToken, "OutputMarshalError", fmt.Sprintf("Failed to marshal initial task output: %v", err))
			log.Fatalf("Error marshalling initial task output: %v\n", err)
		}
	}

	// --- Send Success to Step Functions ---
	log.Println("Sending success to Step Functions...")
	// Log the output being sent
	log.Printf("Output being sent to SFN: %s\n", string(outputJsonBytes))
	sendSuccess(ctx, taskToken, string(outputJsonBytes))
	log.Println("Fargate task finished successfully.")
}

// Helper function to send success
func sendSuccess(ctx context.Context, token, output string) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS SDK config: %v", err)
	}
	sfnClient := sfn.NewFromConfig(cfg)

	_, err = sfnClient.SendTaskSuccess(ctx, &sfn.SendTaskSuccessInput{
		TaskToken: &token,
		Output:    &output,
	})
	if err != nil {
		// If sending success fails, we can't really send failure anymore.
		log.Fatalf("Failed to send task success to Step Functions: %v", err)
	}
	log.Println("Successfully sent task success.")
}

// Helper function to send failure
func sendFailure(ctx context.Context, token, errorCause, errorMessage string) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Printf("Warning: Failed to load AWS SDK config for sending failure: %v", err)
		return // Don't fatal error if we can't report the failure
	}
	sfnClient := sfn.NewFromConfig(cfg)

	_, err = sfnClient.SendTaskFailure(ctx, &sfn.SendTaskFailureInput{
		TaskToken: &token,
		Error:     &errorCause,   // Short error identifier
		Cause:     &errorMessage, // Longer description
	})
	if err != nil {
		log.Printf("Warning: Failed to send task failure to Step Functions: %v", err)
	}
}
