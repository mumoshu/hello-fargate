# Backend Use Case: ECS Service Connect

This use case demonstrates internal service-to-service communication using AWS ECS Service Connect. It implements a two-service architecture where a frontend service calls a backend service through Service Connect's built-in service discovery and load balancing.

## Architecture

```
                 +----------------------------------+
                 |   Cloud Map HTTP Namespace       |
                 |   (hello-fargate-backend.local)  |
                 +----------------------------------+
                                  |
              +-------------------+-------------------+
              |                                       |
     +--------v--------+                    +---------v--------+
     | Frontend Service|                    |  Backend Service |
     |   (count=1)     |--- Service     --->|    (count=2)     |
     | /api/test       |    Connect         | /health          |
     | (public IP)     |  backend:8080      | /api/echo        |
     +-----------------+                    +------------------+
```

## Components

### Backend Service (count=2)
- **Purpose**: Internal service only accessible via Service Connect
- **Endpoints**:
  - `GET /health` - Health check, returns server ID
  - `POST /api/echo` - Echoes request body with server ID
- **Service Connect**: Registers as `backend` in the namespace, discoverable at `http://backend:8080`

### Frontend Service (count=1)
- **Purpose**: Public-facing service that calls Backend via Service Connect
- **Endpoints**:
  - `GET /health` - Health check
  - `GET /api/test?requests=N` - Sends N requests to Backend and reports distribution
- **Service Connect**: Client mode only (can resolve `http://backend:8080`)

## Service Connect Configuration

### Backend (Server Mode)
```hcl
service_connect_configuration {
  enabled   = true
  namespace = aws_service_discovery_http_namespace.backend.arn

  service {
    port_name      = "http"
    discovery_name = "backend"
    client_alias {
      port     = 8080
      dns_name = "backend"
    }
  }
}
```

### Frontend (Client Mode)
```hcl
service_connect_configuration {
  enabled   = true
  namespace = aws_service_discovery_http_namespace.backend.arn
  # No service block = client mode only
}
```

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

# 2. Run test
cd tests/sctest
go build -o sctest .
./sctest \
  -cluster-arn="arn:aws:ecs:..." \
  -backend-service="hello-fargate-backend-backend-service" \
  -frontend-service="hello-fargate-backend-frontend-service"

# 3. Cleanup
./scripts/destroy.sh
```

## Test Verification

The test verifies Service Connect load balancing by:
1. Waiting for both services to have running tasks (backend=2, frontend=1)
2. Getting the frontend task's public IP
3. Calling `GET /api/test?requests=20` on the frontend
4. Frontend makes 20 requests to `http://backend:8080/api/echo`
5. Verifying that at least 2 unique backend server IDs responded

### Expected Output

```
--- Service Connect Test Results ---
Total Requests: 20
Successful: 20
Failed: 0
Unique Backends: 2

Distribution:
  abc123: 11 requests (55.0%)
  def456: 9 requests (45.0%)

Frontend ID: xyz789
Result: SUCCESS: Sent 20 requests, 2 unique backends responded
------------------------------------
Test PASSED: Service Connect load balancing verified!
```

## Key Features Demonstrated

- **Service Discovery**: Frontend resolves `http://backend:8080` via Service Connect without any DNS configuration
- **Load Balancing**: Service Connect (Envoy) automatically distributes requests across backend replicas
- **Health Checking**: Container health checks integrated with Service Connect
- **Internal-Only Access**: Backend has no public IP; only accessible via Service Connect within the namespace

## Infrastructure Resources

| Resource | Description |
|----------|-------------|
| Cloud Map HTTP Namespace | Service Connect namespace (`hello-fargate-backend.local`) |
| ECS Service (Backend) | 2 replicas, server mode |
| ECS Service (Frontend) | 1 replica, client mode |
| Security Groups | Backend: VPC-only ingress; Frontend: public ingress |
| CloudWatch Log Groups | Separate logs for backend, frontend, and Service Connect proxy |

## Troubleshooting

### Frontend can't reach backend
- Check Service Connect logs in CloudWatch (`/ecs/hello-fargate-backend-service-connect`)
- Verify namespace is correctly configured
- Ensure port mapping `name` matches Service Connect `port_name`

### Only one backend receives traffic
- Service Connect uses Envoy's connection pooling
- Increase request count or add delays between requests
- Check that both backend tasks are healthy

### Tasks fail to start
- Check CloudWatch logs for error messages
- Verify security groups allow traffic on port 8080
- Ensure subnets have internet access (for ECR image pull)

## Related Documentation

- [Amazon ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [Service Connect Concepts](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect-concepts.html)
- [Terraform aws_ecs_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service#service_connect_configuration)
