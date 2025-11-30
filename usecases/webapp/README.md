# Webapp Use Case

This use case demonstrates a web application with user authentication using ALB's `authenticate-cognito` action. Users are redirected to Cognito's hosted login page, and after successful authentication, ALB sets a session cookie for subsequent requests.

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────┐      ┌─────────────┐
│   Browser   │─────▶│       ALB       │─────▶│  ECS Task   │      │   Cognito   │
│             │      │ authenticate-   │      │   (webapp)  │      │  User Pool  │
│             │      │ cognito action  │      │             │      │             │
└─────────────┘      └────────┬────────┘      └─────────────┘      └──────┬──────┘
                              │                                           │
                              │  1. Redirect to Cognito login             │
                              │─────────────────────────────────────────▶│
                              │                                           │
                              │  2. User logs in                          │
                              │◀─────────────────────────────────────────│
                              │                                           │
                              │  3. Callback with auth code               │
                              │◀─────────────────────────────────────────│
                              │                                           │
                              │  4. Set session cookie, forward request   │
                              │─────────────────────────────────────────▶│
```

## Key Differences from webapi

| Aspect | webapi | webapp |
|--------|--------|--------|
| ALB Action | `jwt-validation` | `authenticate-cognito` |
| OAuth Flow | `client_credentials` (M2M) | `authorization_code` (user login) |
| Authentication | JWT in Authorization header | Session cookie |
| Use Case | API clients (programmatic) | Browser-based web apps |
| Cognito Users | Not needed (M2M) | Real users required |

## Endpoints

| Endpoint | Auth Required | Description |
|----------|---------------|-------------|
| `GET /health` | No | Health check (bypasses authentication) |
| `GET /app/profile` | Yes | Shows user profile from ALB OIDC headers |

## ALB Headers

When authentication succeeds, ALB adds these headers to requests:

- `X-Amzn-Oidc-Identity`: User's subject claim (sub)
- `X-Amzn-Oidc-Data`: JWT with user claims (signed by ALB)
- `X-Amzn-Oidc-Accesstoken`: OAuth2 access token

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker
- Go 1.23+
- Shared ECS cluster deployed (at `../../infra/terraform/`)

## Quick Start

### Environment Variables

```bash
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TF_VPC_ID="vpc-xxx"  # Your VPC ID
```

### Run E2E Test

```bash
# Run complete E2E test with cleanup
./scripts/run-e2e.sh

# Run without cleanup (for debugging)
./scripts/run-e2e.sh --no-cleanup
```

### Manual Deployment

```bash
# 1. Deploy ECR repository
cd infra/terraform/01-ecr
terraform init && terraform apply

# 2. Build and push Docker image
cd ../../../scripts
./build.sh

# 3. Set Terraform variables
eval $(./set-tf-vars.sh)

# 4. Deploy application infrastructure
cd ../infra/terraform/02-app
terraform init && terraform apply

# 5. Run test
cd ../../../tests/webtest
go build -o webtest .
./webtest \
  -alb-url="$(terraform -chdir=../../infra/terraform/02-app output -raw alb_url)" \
  -cognito-domain="$(terraform -chdir=../../infra/terraform/02-app output -raw cognito_domain)" \
  -region="$AWS_REGION" \
  -client-id="$(terraform -chdir=../../infra/terraform/02-app output -raw cognito_client_id)" \
  -username="testuser@example.com" \
  -password="TestPassword123"
```

### Cleanup

```bash
./scripts/destroy.sh
```

## Test Flow

The test runner performs these steps:

1. **Test 1**: Verify `/health` is accessible without authentication
2. **Test 2**: Verify `/app/profile` redirects to Cognito login when unauthenticated
3. **Test 3**: Authenticate via Cognito:
   - Follow redirect to Cognito login page
   - Extract CSRF token from HTML form
   - Submit login credentials
   - Follow OAuth callback to ALB
   - Verify session cookie is set
4. **Test 4**: Access `/app/profile` with session cookie:
   - Verify 200 OK response
   - Verify user claims are present in response

## Testing Approach

This implementation uses **HTTP-based authentication** instead of a headless browser:

- Uses Go's `net/http` with cookie jar
- Extracts CSRF token from Cognito login HTML
- Submits credentials via POST request
- Follows redirect chain to capture session cookie

**Advantages**:
- No browser dependencies (no Chrome/Chromium)
- Fast and lightweight
- Works in any CI/CD environment

**Fallback**: If HTTP approach fails, consider using `chromedp` for full browser automation.

## Files

```
webapp/
├── apps/webapp/           # Go web application
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── infra/terraform/
│   ├── 01-ecr/           # ECR repository
│   └── 02-app/           # ALB, Cognito, ECS
│       ├── main.tf
│       ├── cognito.tf    # User Pool + test user
│       ├── tls.tf        # Self-signed certificate
│       ├── alb.tf        # authenticate-cognito action
│       └── ecs.tf
├── scripts/
│   ├── build.sh
│   ├── apply.sh
│   ├── destroy.sh
│   ├── set-tf-vars.sh
│   └── run-e2e.sh
├── tests/webtest/        # HTTP-based test runner
│   ├── main.go
│   └── go.mod
└── README.md
```

## Security Notes

- This implementation uses a **self-signed TLS certificate** for simplicity
- The test user password is hardcoded for testing purposes only
- In production, use proper TLS certificates and secure password management
- ALB session cookies are encrypted and signed by AWS
