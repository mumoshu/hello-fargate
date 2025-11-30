# Cognito User Pool for user authentication (authorization_code flow)
resource "aws_cognito_user_pool" "webapp" {
  name = "hello-fargate-webapp-pool"

  # Allow admin to create users
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # Simple password policy for testing
  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# Cognito domain for hosted UI login
resource "aws_cognito_user_pool_domain" "webapp" {
  domain       = "hello-fargate-webapp-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.webapp.id
}

# App Client configured for authorization_code flow (browser login)
resource "aws_cognito_user_pool_client" "webapp" {
  name         = "hello-fargate-webapp-client"
  user_pool_id = aws_cognito_user_pool.webapp.id

  # Generate client secret for authenticate-cognito action
  generate_secret = true

  # OAuth configuration for authorization_code flow
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # Callback URL for ALB
  callback_urls = ["https://${aws_lb.webapp.dns_name}/oauth2/idpresponse"]

  # Auth flows for testing
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

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

# Test user created via Terraform
resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.webapp.id
  username     = "testuser@example.com"

  # Set permanent password (MESSAGE_ACTION = SUPPRESS skips email verification)
  password             = "TestPassword123"
  message_action       = "SUPPRESS"
  force_alias_creation = false

  attributes = {
    email          = "testuser@example.com"
    email_verified = "true"
  }
}

# Outputs
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.webapp.id
}

output "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.webapp.arn
}

output "cognito_domain" {
  description = "The Cognito domain for hosted UI"
  value       = aws_cognito_user_pool_domain.webapp.domain
}

output "cognito_login_url" {
  description = "The Cognito hosted UI login URL"
  value       = "https://${aws_cognito_user_pool_domain.webapp.domain}.auth.${data.aws_region.current.region}.amazoncognito.com/login"
}

output "cognito_client_id" {
  description = "The Cognito App Client ID"
  value       = aws_cognito_user_pool_client.webapp.id
}

output "cognito_client_secret" {
  description = "The Cognito App Client Secret"
  value       = aws_cognito_user_pool_client.webapp.client_secret
  sensitive   = true
}

output "test_user_email" {
  description = "The test user email"
  value       = aws_cognito_user.test_user.username
}

output "test_user_password" {
  description = "The test user password"
  value       = "TestPassword123"
  sensitive   = true
}
