package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// TokenResponse represents the OAuth2 token response from Cognito
type TokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

func main() {
	albURL := flag.String("alb-url", "", "ALB HTTPS URL")
	tokenEndpoint := flag.String("token-endpoint", "", "Cognito OAuth2 token endpoint")
	clientID := flag.String("client-id", "", "Cognito app client ID")
	clientSecret := flag.String("client-secret", "", "Cognito app client secret")
	scope := flag.String("scope", "", "OAuth scope to request")
	timeout := flag.Duration("timeout", 5*time.Minute, "Test timeout")
	flag.Parse()

	if *albURL == "" || *tokenEndpoint == "" || *clientID == "" || *clientSecret == "" || *scope == "" {
		log.Fatal("Required flags: -alb-url, -token-endpoint, -client-id, -client-secret, -scope")
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// Create HTTP client that skips TLS verification (self-signed cert)
	httpClient := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true, // Required for self-signed certificate
			},
		},
	}

	// Wait for ALB health check to pass
	log.Println("Waiting for ALB to be healthy...")
	if err := waitForHealth(ctx, httpClient, *albURL+"/health"); err != nil {
		log.Fatalf("ALB not healthy: %v", err)
	}
	log.Println("ALB is healthy!")

	// Test 1: Unauthenticated request to /health (should succeed - not protected)
	log.Println("\n=== Test 1: Unauthenticated request to /health ===")
	if err := testHealthEndpoint(ctx, httpClient, *albURL+"/health"); err != nil {
		log.Fatalf("Test 1 FAILED: %v", err)
	}
	log.Println("Test 1 PASSED: Health endpoint accessible without authentication")

	// Test 2: Unauthenticated request to /api/echo (should fail with 401)
	log.Println("\n=== Test 2: Unauthenticated request to /api/echo ===")
	if err := testUnauthenticated(ctx, httpClient, *albURL+"/api/echo"); err != nil {
		log.Fatalf("Test 2 FAILED: %v", err)
	}
	log.Println("Test 2 PASSED: Protected endpoint correctly rejected unauthenticated request")

	// Test 3: Get access token from Cognito
	log.Println("\n=== Test 3: Getting access token from Cognito ===")
	token, err := getAccessToken(ctx, *tokenEndpoint, *clientID, *clientSecret, *scope)
	if err != nil {
		log.Fatalf("Test 3 FAILED: Failed to get access token: %v", err)
	}
	log.Printf("Test 3 PASSED: Got access token (length: %d chars)", len(token))

	// Test 4: Authenticated request to /api/echo (should succeed)
	log.Println("\n=== Test 4: Authenticated request to /api/echo ===")
	if err := testAuthenticated(ctx, httpClient, *albURL+"/api/echo", token); err != nil {
		log.Fatalf("Test 4 FAILED: %v", err)
	}
	log.Println("Test 4 PASSED: Protected endpoint accessible with valid JWT")

	// Test 5: Verify /api/whoami returns expected data
	log.Println("\n=== Test 5: Verify /api/whoami endpoint ===")
	if err := testWhoami(ctx, httpClient, *albURL+"/api/whoami", token); err != nil {
		log.Fatalf("Test 5 FAILED: %v", err)
	}
	log.Println("Test 5 PASSED: Whoami endpoint returns server information")

	fmt.Println("\n========================================")
	fmt.Println("All JWT validation tests PASSED!")
	fmt.Println("========================================")
}

func waitForHealth(ctx context.Context, client *http.Client, healthURL string) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, healthURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		resp, err := client.Do(req)
		if err == nil && resp.StatusCode == http.StatusOK {
			resp.Body.Close()
			return nil
		}
		if resp != nil {
			resp.Body.Close()
		}

		log.Printf("Waiting for health check... (error: %v)", err)
		time.Sleep(5 * time.Second)
	}
}

func testHealthEndpoint(ctx context.Context, client *http.Client, url string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	log.Printf("Response status: %d, body: %s", resp.StatusCode, strings.TrimSpace(string(body)))

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200, got %d: %s", resp.StatusCode, body)
	}
	return nil
}

func testUnauthenticated(ctx context.Context, client *http.Client, url string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	log.Printf("Response status: %d, body length: %d", resp.StatusCode, len(body))

	if resp.StatusCode != http.StatusUnauthorized {
		return fmt.Errorf("expected 401, got %d: %s", resp.StatusCode, body)
	}
	return nil
}

func getAccessToken(ctx context.Context, tokenURL, clientID, clientSecret, scope string) (string, error) {
	data := url.Values{}
	data.Set("grant_type", "client_credentials")
	data.Set("scope", scope)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenURL, strings.NewReader(data.Encode()))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(clientID, clientSecret)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	log.Printf("Requesting token from: %s", tokenURL)
	log.Printf("Client ID: %s", clientID)
	log.Printf("Scope: %s", scope)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	log.Printf("Token response status: %d", resp.StatusCode)

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("token request failed with status %d: %s", resp.StatusCode, body)
	}

	var tokenResp TokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", fmt.Errorf("failed to parse token response: %w", err)
	}

	if tokenResp.AccessToken == "" {
		return "", fmt.Errorf("empty access token in response")
	}

	log.Printf("Token type: %s, expires in: %d seconds", tokenResp.TokenType, tokenResp.ExpiresIn)
	return tokenResp.AccessToken, nil
}

func testAuthenticated(ctx context.Context, client *http.Client, url, token string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	log.Printf("Response status: %d, body: %s", resp.StatusCode, strings.TrimSpace(string(body)))

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200, got %d: %s", resp.StatusCode, body)
	}
	return nil
}

func testWhoami(ctx context.Context, client *http.Client, url, token string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	log.Printf("Response status: %d", resp.StatusCode)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("expected 200, got %d: %s", resp.StatusCode, body)
	}

	// Parse response to verify it contains expected fields
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("failed to parse response: %w", err)
	}

	if _, ok := result["server_id"]; !ok {
		return fmt.Errorf("response missing server_id field")
	}
	if _, ok := result["headers"]; !ok {
		return fmt.Errorf("response missing headers field")
	}

	log.Printf("Server ID: %v", result["server_id"])
	return nil
}
