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
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"strings"
	"time"
)

func main() {
	albURL := flag.String("alb-url", "", "ALB HTTPS URL")
	cognitoDomain := flag.String("cognito-domain", "", "Cognito domain (without .auth.region.amazoncognito.com)")
	region := flag.String("region", "", "AWS region")
	clientID := flag.String("client-id", "", "Cognito app client ID")
	username := flag.String("username", "", "Test user email")
	password := flag.String("password", "", "Test user password")
	timeout := flag.Duration("timeout", 5*time.Minute, "Test timeout")
	flag.Parse()

	if *albURL == "" || *cognitoDomain == "" || *region == "" || *clientID == "" || *username == "" || *password == "" {
		log.Fatal("Required flags: -alb-url, -cognito-domain, -region, -client-id, -username, -password")
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// Create HTTP client with cookie jar (to maintain session)
	jar, err := cookiejar.New(nil)
	if err != nil {
		log.Fatalf("Failed to create cookie jar: %v", err)
	}

	// Client that follows redirects (for health check)
	httpClient := &http.Client{
		Timeout: 30 * time.Second,
		Jar:     jar,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true, // Required for self-signed certificate
			},
		},
	}

	// Client that does NOT follow redirects (for testing redirect behavior)
	noRedirectClient := &http.Client{
		Timeout: 30 * time.Second,
		Jar:     jar,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	// Wait for ALB health check to pass
	log.Println("Waiting for ALB to be healthy...")
	if err := waitForHealth(ctx, httpClient, *albURL+"/health"); err != nil {
		log.Fatalf("ALB not healthy: %v", err)
	}
	log.Println("ALB is healthy!")

	// Test 1: Health endpoint (unauthenticated)
	log.Println("\n=== Test 1: Unauthenticated request to /health ===")
	if err := testHealthEndpoint(ctx, httpClient, *albURL+"/health"); err != nil {
		log.Fatalf("Test 1 FAILED: %v", err)
	}
	log.Println("Test 1 PASSED: Health endpoint accessible without authentication")

	// Test 2: Unauthenticated request to /app/profile should redirect to Cognito
	log.Println("\n=== Test 2: Unauthenticated request to /app/profile ===")
	if err := testUnauthenticatedRedirect(ctx, noRedirectClient, *albURL+"/app/profile"); err != nil {
		log.Fatalf("Test 2 FAILED: %v", err)
	}
	log.Println("Test 2 PASSED: Protected endpoint correctly redirects to Cognito login")

	// Test 3: Authenticate via HTTP-based Cognito login flow
	log.Println("\n=== Test 3: Authenticate via Cognito login ===")
	cognitoBaseURL := fmt.Sprintf("https://%s.auth.%s.amazoncognito.com", *cognitoDomain, *region)
	if err := authenticateViaCognito(ctx, noRedirectClient, httpClient, *albURL, cognitoBaseURL, *clientID, *username, *password); err != nil {
		log.Fatalf("Test 3 FAILED: %v", err)
	}
	log.Println("Test 3 PASSED: Successfully authenticated and obtained session cookie")

	// Test 4: Access protected endpoint with session cookie
	log.Println("\n=== Test 4: Authenticated request to /app/profile ===")
	if err := testAuthenticatedProfile(ctx, httpClient, *albURL+"/app/profile"); err != nil {
		log.Fatalf("Test 4 FAILED: %v", err)
	}
	log.Println("Test 4 PASSED: Protected endpoint accessible with session cookie, user claims verified")

	fmt.Println("\n========================================")
	fmt.Println("All webapp authentication tests PASSED!")
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

func testUnauthenticatedRedirect(ctx context.Context, client *http.Client, url string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	log.Printf("Response status: %d", resp.StatusCode)

	// ALB authenticate-cognito returns 302 redirect to Cognito
	if resp.StatusCode != http.StatusFound {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("expected 302 redirect, got %d: %s", resp.StatusCode, body)
	}

	location := resp.Header.Get("Location")
	log.Printf("Redirect location: %s", location)

	if !strings.Contains(location, "amazoncognito.com") {
		return fmt.Errorf("redirect not to Cognito: %s", location)
	}

	return nil
}

func authenticateViaCognito(ctx context.Context, noRedirectClient, httpClient *http.Client, albURL, cognitoBaseURL, clientID, username, password string) error {
	// Step 1: Request protected endpoint to get redirected to Cognito
	log.Println("Step 1: Initiating OAuth flow by requesting protected endpoint...")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, albURL+"/app/profile", nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := noRedirectClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	resp.Body.Close()

	if resp.StatusCode != http.StatusFound {
		return fmt.Errorf("expected 302 redirect, got %d", resp.StatusCode)
	}

	// Get the redirect URL to Cognito
	cognitoAuthURL := resp.Header.Get("Location")
	log.Printf("Step 1: Got Cognito auth URL: %s", truncateString(cognitoAuthURL, 100))

	// Step 2: Follow redirect to Cognito login page
	log.Println("Step 2: Following redirect to Cognito login page...")
	req, err = http.NewRequestWithContext(ctx, http.MethodGet, cognitoAuthURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err = noRedirectClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}

	// The response might be another redirect or the login form
	loginPageURL := cognitoAuthURL
	if resp.StatusCode == http.StatusFound {
		loginPageURL = resp.Header.Get("Location")
		resp.Body.Close()

		// Follow redirect to actual login page
		req, err = http.NewRequestWithContext(ctx, http.MethodGet, loginPageURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		resp, err = httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
	}

	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	log.Printf("Step 2: Login page status: %d, body length: %d", resp.StatusCode, len(body))

	// Step 3: Extract CSRF token from login form
	log.Println("Step 3: Extracting CSRF token from login form...")
	csrfToken := extractCSRFToken(string(body))
	if csrfToken == "" {
		// Try alternative extraction methods
		csrfToken = extractCSRFTokenAlt(string(body))
	}
	if csrfToken == "" {
		log.Printf("Login page HTML (first 2000 chars): %s", truncateString(string(body), 2000))
		return fmt.Errorf("failed to extract CSRF token from login page")
	}
	log.Printf("Step 3: Extracted CSRF token: %s", truncateString(csrfToken, 20))

	// Step 4: Submit login form
	log.Println("Step 4: Submitting login form...")
	loginURL := cognitoBaseURL + "/login"

	// Parse the original auth URL to get query params
	parsedAuthURL, _ := url.Parse(cognitoAuthURL)
	formData := url.Values{
		"_csrf":       {csrfToken},
		"username":    {username},
		"password":    {password},
		"cognitoAsfData": {""}, // Optional, can be empty
	}

	// Add any query params from the auth URL
	for key, values := range parsedAuthURL.Query() {
		if key != "response_type" && key != "scope" {
			formData[key] = values
		}
	}

	req, err = http.NewRequestWithContext(ctx, http.MethodPost, loginURL+"?"+parsedAuthURL.RawQuery, strings.NewReader(formData.Encode()))
	if err != nil {
		return fmt.Errorf("failed to create login request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err = noRedirectClient.Do(req)
	if err != nil {
		return fmt.Errorf("login request failed: %w", err)
	}
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()

	log.Printf("Step 4: Login response status: %d", resp.StatusCode)

	// Step 5: Follow redirect chain to ALB callback
	log.Println("Step 5: Following redirect chain to ALB callback...")
	redirectCount := 0
	maxRedirects := 10
	currentURL := resp.Header.Get("Location")

	for resp.StatusCode == http.StatusFound && redirectCount < maxRedirects {
		log.Printf("Step 5: Following redirect to: %s", truncateString(currentURL, 100))

		req, err = http.NewRequestWithContext(ctx, http.MethodGet, currentURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create redirect request: %w", err)
		}

		resp, err = noRedirectClient.Do(req)
		if err != nil {
			return fmt.Errorf("redirect request failed: %w", err)
		}
		resp.Body.Close()

		if resp.StatusCode == http.StatusFound {
			currentURL = resp.Header.Get("Location")
			redirectCount++
		} else {
			break
		}
	}

	log.Printf("Step 5: Final response status: %d after %d redirects", resp.StatusCode, redirectCount)

	// Step 6: Verify session cookie was set
	log.Println("Step 6: Verifying session cookie...")
	albParsedURL, _ := url.Parse(albURL)
	cookies := noRedirectClient.Jar.Cookies(albParsedURL)

	var sessionCookie *http.Cookie
	for _, c := range cookies {
		log.Printf("Found cookie: %s (domain: implied)", c.Name)
		if strings.HasPrefix(c.Name, "AWSELBAuthSessionCookie") {
			sessionCookie = c
		}
	}

	if sessionCookie == nil {
		return fmt.Errorf("session cookie not found after authentication")
	}

	log.Printf("Step 6: Session cookie found: %s (length: %d)", sessionCookie.Name, len(sessionCookie.Value))
	return nil
}

func testAuthenticatedProfile(ctx context.Context, client *http.Client, profileURL string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, profileURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

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

	log.Printf("Profile response: %s", strings.TrimSpace(string(body)))

	// Verify user_id is present (from X-Amzn-Oidc-Identity header)
	if userID, ok := result["user_id"]; !ok || userID == "" {
		return fmt.Errorf("response missing user_id field")
	}

	// Verify claims are present (from X-Amzn-Oidc-Data header)
	if claims, ok := result["claims"]; !ok || claims == nil {
		return fmt.Errorf("response missing claims field")
	}

	// Verify has_token is true (from X-Amzn-Oidc-Accesstoken header)
	if hasToken, ok := result["has_token"].(bool); !ok || !hasToken {
		return fmt.Errorf("response indicates no access token was provided")
	}

	log.Printf("User ID: %v", result["user_id"])
	return nil
}

// extractCSRFToken extracts the CSRF token from the Cognito login page HTML
func extractCSRFToken(html string) string {
	// Look for: <input type="hidden" name="_csrf" value="...">
	re := regexp.MustCompile(`name="_csrf"\s+value="([^"]+)"`)
	matches := re.FindStringSubmatch(html)
	if len(matches) > 1 {
		return matches[1]
	}

	// Try alternative pattern: value="..." name="_csrf"
	re = regexp.MustCompile(`value="([^"]+)"\s+name="_csrf"`)
	matches = re.FindStringSubmatch(html)
	if len(matches) > 1 {
		return matches[1]
	}

	return ""
}

// extractCSRFTokenAlt tries alternative patterns to find the CSRF token
func extractCSRFTokenAlt(html string) string {
	// Pattern: name="_csrf" followed by value on same or next attribute
	patterns := []string{
		`<input[^>]*name="_csrf"[^>]*value="([^"]+)"`,
		`<input[^>]*value="([^"]+)"[^>]*name="_csrf"`,
		`name=['"]_csrf['"][^>]*value=['"]([^'"]+)['"]`,
		`value=['"]([^'"]+)['"][^>]*name=['"]_csrf['"]`,
	}

	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		matches := re.FindStringSubmatch(html)
		if len(matches) > 1 {
			return matches[1]
		}
	}

	return ""
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
