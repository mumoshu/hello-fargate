# Troubleshooting

## Frontend can't reach backend
- Check Service Connect logs in CloudWatch (`/ecs/hello-fargate-backend-service-connect`)
- Verify namespace is correctly configured
- Ensure port mapping `name` matches Service Connect `port_name`

## Only one backend receives traffic
- Service Connect uses Envoy's connection pooling
- Increase request count or add delays between requests
- Check that both backend tasks are healthy

## Tasks fail to start
- Check CloudWatch logs for error messages
- Verify security groups allow traffic on port 8080
- Ensure subnets have internet access (for ECR image pull)
