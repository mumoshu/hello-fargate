package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// HealthResponse represents the health check response
type HealthResponse struct {
	Status   string `json:"status"`
	ServerID string `json:"server_id"`
}

// BackendEchoResponse represents the response from backend's /api/echo
type BackendEchoResponse struct {
	Message   string                 `json:"message"`
	ServerID  string                 `json:"server_id"`
	Timestamp string                 `json:"timestamp"`
	Echo      map[string]interface{} `json:"echo,omitempty"`
}

// TestResponse represents the /api/test endpoint response
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

var (
	serverID   string
	backendURL string
)

func init() {
	// Use container hostname as unique server ID
	var err error
	serverID, err = os.Hostname()
	if err != nil {
		serverID = "unknown"
	}

	// Backend URL from environment (defaults to Service Connect endpoint)
	backendURL = os.Getenv("BACKEND_URL")
	if backendURL == "" {
		backendURL = "http://backend:8080"
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/test", testHandler)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		log.Printf("Received signal %v, initiating graceful shutdown...", sig)

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("Server shutdown error: %v", err)
		}
	}()

	log.Printf("Frontend server starting on port %s (Server ID: %s)", port, serverID)
	log.Printf("Backend URL: %s", backendURL)

	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}

	log.Println("Server stopped gracefully")
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	resp := HealthResponse{
		Status:   "healthy",
		ServerID: serverID,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func testHandler(w http.ResponseWriter, r *http.Request) {
	// Get number of requests from query param (default 20)
	requestCountStr := r.URL.Query().Get("requests")
	requestCount := 20
	if requestCountStr != "" {
		if n, err := strconv.Atoi(requestCountStr); err == nil && n > 0 {
			requestCount = n
		}
	}

	log.Printf("Starting test with %d requests to backend", requestCount)

	// Track responses from each backend server
	distribution := make(map[string]int)
	successCount := 0
	failureCount := 0

	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	for i := 0; i < requestCount; i++ {
		payload := fmt.Sprintf(`{"request_number": %d, "frontend_id": "%s"}`, i, serverID)

		resp, err := client.Post(
			backendURL+"/api/echo",
			"application/json",
			strings.NewReader(payload),
		)
		if err != nil {
			log.Printf("Request %d failed: %v", i, err)
			failureCount++
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()

		if err != nil {
			log.Printf("Request %d: failed to read response: %v", i, err)
			failureCount++
			continue
		}

		if resp.StatusCode != http.StatusOK {
			log.Printf("Request %d: unexpected status %d", i, resp.StatusCode)
			failureCount++
			continue
		}

		var echoResp BackendEchoResponse
		if err := json.Unmarshal(body, &echoResp); err != nil {
			log.Printf("Request %d: failed to parse response: %v", i, err)
			failureCount++
			continue
		}

		distribution[echoResp.ServerID]++
		successCount++
		log.Printf("Request %d: handled by backend %s", i, echoResp.ServerID)

		// Small delay to allow load balancing
		time.Sleep(50 * time.Millisecond)
	}

	// Determine success (at least 2 unique backends)
	uniqueBackends := len(distribution)
	success := uniqueBackends >= 2

	message := fmt.Sprintf("Sent %d requests, %d unique backends responded", requestCount, uniqueBackends)
	if success {
		message = "SUCCESS: " + message
	} else {
		message = "FAIL: " + message + " (expected at least 2)"
	}

	result := TestResponse{
		TotalRequests:  requestCount,
		SuccessCount:   successCount,
		FailureCount:   failureCount,
		UniqueBackends: uniqueBackends,
		Distribution:   distribution,
		Success:        success,
		Message:        message,
		FrontendID:     serverID,
	}

	log.Printf("Test completed: %s", message)
	for backendID, count := range distribution {
		log.Printf("  Backend %s: %d requests (%.1f%%)", backendID, count, float64(count)/float64(requestCount)*100)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
