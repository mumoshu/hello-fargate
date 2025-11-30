# Application Load Balancer with authenticate-cognito action

# Data sources
data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "hello-fargate-webapp-alb-sg"
  description = "Security group for Webapp ALB"
  vpc_id      = var.vpc_id

  # Allow HTTPS from anywhere
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (for redirects)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# Application Load Balancer
resource "aws_lb" "webapp" {
  name               = "hello-fargate-webapp-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.vpc_subnets.ids

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# Target Group for ECS Service
resource "aws_lb_target_group" "webapp" {
  name        = "hello-fargate-webapp-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# HTTPS Listener with default forward action (for /health)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.webapp.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  # Default action: forward to target group (for unprotected /health)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp.arn
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# Cognito-protected rule for /app/* paths
# Uses ALB authenticate-cognito action for user login flow
resource "aws_lb_listener_rule" "cognito_protected" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  # Action 1: Authenticate with Cognito (redirects to login page if not authenticated)
  action {
    type  = "authenticate-cognito"
    order = 1

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.webapp.arn
      user_pool_client_id = aws_cognito_user_pool_client.webapp.id
      user_pool_domain    = aws_cognito_user_pool_domain.webapp.domain

      # Redirect unauthenticated requests to Cognito login
      on_unauthenticated_request = "authenticate"

      # Session configuration
      session_cookie_name = "AWSELBAuthSessionCookie"
      session_timeout     = 3600  # 1 hour

      # OAuth scopes to request
      scope = "openid email profile"
    }
  }

  # Action 2: Forward to target group if authenticated
  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.webapp.arn
  }

  condition {
    path_pattern {
      values = ["/app/*"]
    }
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# HTTP Listener - redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.webapp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

# Outputs
output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.webapp.dns_name
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.webapp.arn
}

output "alb_url" {
  description = "The HTTPS URL of the ALB"
  value       = "https://${aws_lb.webapp.dns_name}"
}

output "target_group_arn" {
  description = "The ARN of the target group"
  value       = aws_lb_target_group.webapp.arn
}

output "callback_url" {
  description = "The OAuth2 callback URL for ALB"
  value       = "https://${aws_lb.webapp.dns_name}/oauth2/idpresponse"
}
