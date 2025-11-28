package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
)

// TaskInput represents the input JSON structure
type TaskInput struct {
	Message string                 `json:"message"`
	Data    map[string]interface{} `json:"data,omitempty"`
}

// TaskOutput represents the output JSON structure
type TaskOutput struct {
	Status  string                 `json:"status"`
	Message string                 `json:"message"`
	Input   map[string]interface{} `json:"input,omitempty"`
}

func main() {
	log.Println("One-off Fargate task started.")

	// Get task input from environment variable
	inputJsonString := os.Getenv("TASK_INPUT")
	if inputJsonString == "" {
		inputJsonString = "{}"
		log.Println("No TASK_INPUT provided, using empty object.")
	}

	// Parse the input JSON
	var taskInput TaskInput
	if err := json.Unmarshal([]byte(inputJsonString), &taskInput); err != nil {
		log.Printf("Warning: Failed to parse TASK_INPUT as structured input: %v\n", err)
		// Try to parse as generic map
		var genericInput map[string]interface{}
		if err := json.Unmarshal([]byte(inputJsonString), &genericInput); err != nil {
			log.Fatalf("Error: Failed to parse TASK_INPUT: %v\n", err)
		}
		taskInput.Data = genericInput
	}

	log.Printf("Received input: %+v\n", taskInput)

	// Process the input (simple example - just echo back with status)
	output := TaskOutput{
		Status:  "success",
		Message: fmt.Sprintf("Processed: %s", taskInput.Message),
		Input:   taskInput.Data,
	}

	if taskInput.Message == "" {
		output.Message = "Processed successfully (no message provided)"
	}

	// Output the result as JSON
	outputBytes, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		log.Fatalf("Error: Failed to marshal output: %v\n", err)
	}

	fmt.Println("--- Task Output ---")
	fmt.Println(string(outputBytes))
	fmt.Println("-------------------")

	log.Println("One-off Fargate task completed successfully.")
}
