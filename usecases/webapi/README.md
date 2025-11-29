# WebAPI Use Case: ALB JWT Validation with Cognito

This use case demonstrates API-only web services behind AWS ALB with JWT authentication using the ALB's `jwt-validation` action (November 2025 feature) and Amazon Cognito as the OIDC provider.

## Architecture

```
                    +---------------------+
                    |  Cognito User Pool  |
                    |  + App Client       |
                    |  (client_credentials)|
                    +----------+----------+
                               |
         JWKS: https://cognito-idp.{region}.amazonaws.com/{poolId}/.well-known/jwks.json
         Token: https://{domain}.auth.{region}.amazoncognito.com/oauth2/token
                               |
    +--------------------------+---------------------------+
    |                          v                           |
    |                  +---------------+                   |
    |                  |  Test Runner  |                   |
    |                  +-------+-------+                   |
    |                          |                           |
    |     1. Get token from Cognito (client_credentials)   |
    |     2. Send requests to ALB                          |
    |                          |                           |
    |         +--------------------------------+            |
    |         |  ALB (HTTPS:443)               |            |
    |         |  Self-signed cert              |            |
    |         +--------------------------------+            |
    |                          |                           |
    |    jwt-validation action |  (validates against       |
    |    on /api/* paths       |   Cognito JWKS)           |
    |                          |                           |
    |         +--------------------------------+            |
    |         |  ECS Service (Fargate)         |            |
    |         |  Go API Server                 |            |
    |         +--------------------------------+            |
    +------------------------------------------------------+
```

## Components

### API Service
- **Endpoints**:
  - `GET /health` - Health check (unauthenticated)
  - `GET /api/echo` - Protected endpoint (requires valid JWT)
  - `GET /api/whoami` - Returns request headers (protected)

### Cognito
- **User Pool**: Provides JWKS endpoint for JWT validation
- **Resource Server**: Defines custom scopes (`read`, `write`)
- **App Client**: Configured for `client_credentials` OAuth flow (M2M)

### ALB
- **HTTPS Listener**: Uses self-signed certificate (no Route53 needed)
- **jwt-validation Rule**: Validates JWT for `/api/*` paths using Cognito JWKS
- **Default Rule**: Forwards unauthenticated traffic to `/health`

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Docker installed and running
- Go 1.23+ installed
- Terraform 1.0+ installed

### Environment Setup

```bash
export AWS_REGION="ap-northeast-1"
export AWS_ACCOUNT_ID="your-account-id"
export TF_VPC_ID="vpc-xxx"  # VPC with internet access
```

### Run End-to-End Test

```bash
# Full E2E test with automatic cleanup
./scripts/run-e2e.sh

# Keep infrastructure for debugging
./scripts/run-e2e.sh --no-cleanup
```

### Manual Deployment

```bash
# 1. Deploy infrastructure
./scripts/apply.sh

# 2. Run test manually
cd tests/apitest
go build -o apitest .
./apitest \
  -alb-url="https://xxx.elb.amazonaws.com" \
  -token-endpoint="https://xxx.auth.ap-northeast-1.amazoncognito.com/oauth2/token" \
  -client-id="xxx" \
  -client-secret="xxx" \
  -scope="https://api.webapi.local/read"

# 3. Cleanup
./scripts/destroy.sh
```

## Test Verification

The test runner performs the following tests:

1. **Health Check**: `GET /health` without token → 200 OK
2. **Unauthenticated API**: `GET /api/echo` without token → 401 Unauthorized
3. **Get Token**: Request access token from Cognito using `client_credentials` grant
4. **Authenticated API**: `GET /api/echo` with Bearer token → 200 OK
5. **Whoami**: `GET /api/whoami` with Bearer token → 200 OK with server info

### Expected Output

```
=== Test 1: Unauthenticated request to /health ===
Test 1 PASSED: Health endpoint accessible without authentication

=== Test 2: Unauthenticated request to /api/echo ===
Test 2 PASSED: Protected endpoint correctly rejected unauthenticated request

=== Test 3: Getting access token from Cognito ===
Test 3 PASSED: Got access token (length: xxx chars)

=== Test 4: Authenticated request to /api/echo ===
Test 4 PASSED: Protected endpoint accessible with valid JWT

=== Test 5: Verify /api/whoami endpoint ===
Test 5 PASSED: Whoami endpoint returns server information

========================================
All JWT validation tests PASSED!
========================================
```

## Key Features Demonstrated

- **ALB jwt-validation Action**: Native JWT validation at the edge (November 2025 feature)
- **Self-Signed Certificate**: HTTPS without Route53 or ACM validation
- **Cognito M2M Authentication**: Client credentials flow for API authentication
- **JWKS Integration**: ALB fetches public keys from Cognito JWKS endpoint

## Infrastructure Resources

| Resource | Description |
|----------|-------------|
| Cognito User Pool | OIDC provider with JWKS endpoint |
| Cognito App Client | M2M client with `client_credentials` flow |
| ACM Certificate | Self-signed, imported into ACM |
| ALB | Internet-facing (or internal) load balancer |
| ALB Listener | HTTPS on port 443 with jwt-validation |
| Target Group | Routes to ECS service on port 8080 |
| ECS Service | Fargate service running Go API |
| Security Groups | ALB (443, 80 ingress), ECS (8080 from ALB) |

## Making ALB Internal

To make the ALB internal (for internal APIs), set the `internal` variable:

```hcl
# In terraform.tfvars or via -var
internal = true
```

Or via environment variable:
```bash
export TF_VAR_internal=true
```

## Troubleshooting

### JWT Validation Fails
- Check ALB listener rule logs in CloudWatch
- Verify Cognito JWKS URL is accessible
- Ensure token hasn't expired (`exp` claim)

### 401 on All Requests
- Verify `Authorization: Bearer <token>` header format
- Check that token includes required scope
- Verify ALB listener rule path pattern matches

### Certificate Errors
- Test runner uses `InsecureSkipVerify: true` for self-signed cert
- For browser testing, accept the self-signed certificate warning

### ECS Tasks Not Starting
- Check CloudWatch logs at `/ecs/hello-fargate-webapi`
- Verify security groups allow traffic from ALB

## Related Documentation

- [AWS ALB JWT Verification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-verify-jwt.html)
- [Amazon Cognito User Pools](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
- [OAuth 2.0 Client Credentials Grant](https://oauth.net/2/grant-types/client-credentials/)
- [Terraform aws_lb_listener_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule)
