package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
)

// JobInput represents the input JSON structure
type JobInput struct {
	Message string                 `json:"message"`
	Items   []string               `json:"items,omitempty"`
	Data    map[string]interface{} `json:"data,omitempty"`
}

// JobOutput represents the output JSON structure
type JobOutput struct {
	Status     string                 `json:"status"`
	Message    string                 `json:"message"`
	ArrayIndex string                 `json:"arrayIndex,omitempty"`
	JobID      string                 `json:"jobId,omitempty"`
	Input      map[string]interface{} `json:"input,omitempty"`
}

func main() {
	log.Println("AWS Batch job started.")

	// Get array job index (auto-set by AWS Batch for array jobs)
	// Empty string for non-array jobs
	arrayIndex := os.Getenv("AWS_BATCH_JOB_ARRAY_INDEX")
	jobID := os.Getenv("AWS_BATCH_JOB_ID")

	if arrayIndex != "" {
		log.Printf("Running as array job index: %s\n", arrayIndex)
	} else {
		log.Println("Running as single job (not an array job)")
	}

	// Get job input from environment variable
	inputJSONString := os.Getenv("JOB_INPUT")
	if inputJSONString == "" {
		inputJSONString = "{}"
		log.Println("No JOB_INPUT provided, using empty object.")
	}

	// Parse the input JSON
	var jobInput JobInput
	if err := json.Unmarshal([]byte(inputJSONString), &jobInput); err != nil {
		log.Printf("Warning: Failed to parse JOB_INPUT as structured input: %v\n", err)
		// Try to parse as generic map
		var genericInput map[string]interface{}
		if err := json.Unmarshal([]byte(inputJSONString), &genericInput); err != nil {
			log.Fatalf("Error: Failed to parse JOB_INPUT: %v\n", err)
		}
		jobInput.Data = genericInput
	}

	log.Printf("Received input: %+v\n", jobInput)

	// Process the input based on array index
	output := processJob(arrayIndex, jobID, jobInput)

	// Output the result as JSON
	outputBytes, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		log.Fatalf("Error: Failed to marshal output: %v\n", err)
	}

	fmt.Println("--- Job Output ---")
	fmt.Println(string(outputBytes))
	fmt.Println("------------------")

	log.Println("AWS Batch job completed successfully.")
}

func processJob(arrayIndex, jobID string, input JobInput) JobOutput {
	output := JobOutput{
		Status:     "success",
		ArrayIndex: arrayIndex,
		JobID:      jobID,
		Input:      input.Data,
	}

	// For array jobs, process the item at the given index
	if arrayIndex != "" && len(input.Items) > 0 {
		// Parse array index
		var idx int
		fmt.Sscanf(arrayIndex, "%d", &idx)

		if idx < len(input.Items) {
			output.Message = fmt.Sprintf("Processed item[%d]: %s", idx, input.Items[idx])
		} else {
			output.Message = fmt.Sprintf("Array index %d out of range (items: %d)", idx, len(input.Items))
		}
	} else if input.Message != "" {
		output.Message = fmt.Sprintf("Processed: %s (index: %s)", input.Message, arrayIndex)
	} else {
		output.Message = fmt.Sprintf("Processed successfully (array index: %s)", arrayIndex)
	}

	return output
}
