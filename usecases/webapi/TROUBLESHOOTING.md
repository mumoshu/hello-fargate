# Troubleshooting

## JWT Validation Fails
- Check ALB listener rule logs in CloudWatch
- Verify Cognito JWKS URL is accessible
- Ensure token hasn't expired (`exp` claim)

## 401 on All Requests
- Verify `Authorization: Bearer <token>` header format
- Check that token includes required scope
- Verify ALB listener rule path pattern matches

## Certificate Errors
- Test runner uses `InsecureSkipVerify: true` for self-signed cert
- For browser testing, accept the self-signed certificate warning

## ECS Tasks Not Starting
- Check CloudWatch logs at `/ecs/hello-fargate-webapi`
- Verify security groups allow traffic from ALB
