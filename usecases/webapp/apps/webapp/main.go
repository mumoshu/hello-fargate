package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
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
	mux.HandleFunc("/app/profile", profileHandler)

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

	log.Printf("Webapp server starting on port %s (server_id: %s)", port, serverID)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
	log.Println("Server stopped")
}

// healthHandler returns health status (unauthenticated - bypasses authenticate-cognito rule)
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "healthy",
		"server_id": serverID,
	})
}

// profileHandler returns user profile from ALB OIDC headers
// This endpoint is protected by ALB authenticate-cognito action
func profileHandler(w http.ResponseWriter, r *http.Request) {
	// When ALB authenticate-cognito succeeds, it adds these headers:
	// - X-Amzn-Oidc-Identity: User's subject claim (sub)
	// - X-Amzn-Oidc-Data: JWT containing user claims (signed by ALB)
	// - X-Amzn-Oidc-Accesstoken: The OAuth2 access token

	userID := r.Header.Get("X-Amzn-Oidc-Identity")
	oidcData := r.Header.Get("X-Amzn-Oidc-Data")
	accessToken := r.Header.Get("X-Amzn-Oidc-Accesstoken")

	// Decode user claims from OIDC data JWT
	claims := decodeOIDCData(oidcData)

	// Build response
	response := map[string]interface{}{
		"message":      "Welcome to your profile",
		"server_id":    serverID,
		"user_id":      userID,
		"claims":       claims,
		"has_token":    accessToken != "",
		"token_length": len(accessToken),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// decodeOIDCData decodes the JWT payload from ALB's X-Amzn-Oidc-Data header
// Note: In production, you should verify the JWT signature using ALB's public key
func decodeOIDCData(data string) map[string]interface{} {
	if data == "" {
		return nil
	}

	// JWT format: header.payload.signature
	parts := strings.Split(data, ".")
	if len(parts) < 2 {
		return nil
	}

	// Decode payload (second part) - add padding if needed
	payload := parts[1]
	switch len(payload) % 4 {
	case 2:
		payload += "=="
	case 3:
		payload += "="
	}

	decoded, err := base64.URLEncoding.DecodeString(payload)
	if err != nil {
		log.Printf("Failed to decode OIDC data: %v", err)
		return nil
	}

	var claims map[string]interface{}
	if err := json.Unmarshal(decoded, &claims); err != nil {
		log.Printf("Failed to parse OIDC claims: %v", err)
		return nil
	}

	return claims
}
