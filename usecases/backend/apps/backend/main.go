package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// HealthResponse represents the health check response
type HealthResponse struct {
	Status   string `json:"status"`
	ServerID string `json:"server_id"`
}

// EchoResponse represents the echo endpoint response
type EchoResponse struct {
	Message   string                 `json:"message"`
	ServerID  string                 `json:"server_id"`
	Timestamp string                 `json:"timestamp"`
	Echo      map[string]interface{} `json:"echo,omitempty"`
}

var serverID string

func init() {
	// Use container hostname as unique server ID
	var err error
	serverID, err = os.Hostname()
	if err != nil {
		serverID = "unknown"
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/echo", echoHandler)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
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

	log.Printf("Backend server starting on port %s (Server ID: %s)", port, serverID)

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

func echoHandler(w http.ResponseWriter, r *http.Request) {
	var input map[string]interface{}

	if r.Method == http.MethodPost && r.Body != nil {
		json.NewDecoder(r.Body).Decode(&input)
	}

	resp := EchoResponse{
		Message:   "Echo from backend service",
		ServerID:  serverID,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Echo:      input,
	}

	log.Printf("Echo request handled by Server ID: %s", serverID)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
