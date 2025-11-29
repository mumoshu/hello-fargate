# Cognito User Pool for JWT authentication
resource "aws_cognito_user_pool" "api" {
  name = "hello-fargate-webapi-pool"

  # Minimal configuration - no actual users needed for M2M
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# Cognito domain for token endpoint
resource "aws_cognito_user_pool_domain" "api" {
  domain       = "hello-fargate-webapi-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.api.id
}

# Resource Server (defines custom scopes)
resource "aws_cognito_resource_server" "api" {
  identifier   = "https://api.webapi.local"
  name         = "webapi"
  user_pool_id = aws_cognito_user_pool.api.id

  scope {
    scope_name        = "read"
    scope_description = "Read access to API"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access to API"
  }
}

# App Client with client_credentials flow for M2M authentication
resource "aws_cognito_user_pool_client" "api" {
  name         = "hello-fargate-webapi-client"
  user_pool_id = aws_cognito_user_pool.api.id

  # Generate client secret for client_credentials flow
  generate_secret = true

  # OAuth configuration
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.api.identifier}/read"]
  supported_identity_providers         = ["COGNITO"]

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# Outputs
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.api.id
}

output "cognito_issuer" {
  description = "The issuer URL for JWT validation"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.api.id}"
}

output "cognito_jwks_url" {
  description = "The JWKS URL for JWT validation"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.api.id}/.well-known/jwks.json"
}

output "cognito_token_endpoint" {
  description = "The OAuth2 token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.api.domain}.auth.${data.aws_region.current.region}.amazoncognito.com/oauth2/token"
}

output "cognito_client_id" {
  description = "The Cognito App Client ID"
  value       = aws_cognito_user_pool_client.api.id
}

output "cognito_client_secret" {
  description = "The Cognito App Client Secret"
  value       = aws_cognito_user_pool_client.api.client_secret
  sensitive   = true
}

output "cognito_scope" {
  description = "The OAuth scope to request"
  value       = "${aws_cognito_resource_server.api.identifier}/read"
}
