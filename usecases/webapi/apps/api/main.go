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

var serverID string

func init() {
	serverID, _ = os.Hostname()
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/echo", echoHandler)
	mux.HandleFunc("/api/whoami", whoamiHandler)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// Graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		log.Println("Shutting down server...")
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if err := server.Shutdown(ctx); err != nil {
			log.Printf("Server shutdown error: %v", err)
		}
	}()

	log.Printf("API server starting on port %s (server_id: %s)", port, serverID)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
	log.Println("Server stopped")
}

// healthHandler returns health status (unauthenticated - bypasses jwt-validation rule)
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "healthy",
		"server_id": serverID,
	})
}

// echoHandler returns a simple response (protected by ALB jwt-validation)
func echoHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":   "Hello from protected API",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"server_id": serverID,
	})
}

// whoamiHandler returns request headers (useful for debugging ALB-added headers)
func whoamiHandler(w http.ResponseWriter, r *http.Request) {
	// Convert headers to a simple map for cleaner JSON output
	headers := make(map[string]string)
	for name, values := range r.Header {
		if len(values) > 0 {
			headers[name] = values[0]
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"server_id": serverID,
		"method":    r.Method,
		"path":      r.URL.Path,
		"headers":   headers,
	})
}
