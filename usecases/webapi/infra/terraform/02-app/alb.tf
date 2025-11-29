# Application Load Balancer with JWT validation

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
  name        = "hello-fargate-webapi-alb-sg"
  description = "Security group for WebAPI ALB"
  vpc_id      = var.vpc_id

  # Allow HTTPS from anywhere
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (for health checks or redirects)
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
    Project = "hello-fargate-webapi"
  }
}

# Application Load Balancer
resource "aws_lb" "api" {
  name               = "hello-fargate-webapi-alb"
  internal           = var.internal # Set to true for internal API
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.vpc_subnets.ids

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# Target Group for ECS Service
resource "aws_lb_target_group" "api" {
  name        = "hello-fargate-webapi-tg"
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
    Project = "hello-fargate-webapi"
  }
}

# HTTPS Listener with default forward action
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  # Default action: forward to target group (for non-API paths like /health)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# JWT-protected rule for /api/* paths
# Uses the new ALB jwt-validation action (November 2025 feature)
resource "aws_lb_listener_rule" "jwt_protected" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  # Action 1: Validate JWT using Cognito JWKS
  # By default, requests without valid JWT are denied (401 Unauthorized)
  action {
    type  = "jwt-validation"
    order = 1

    jwt_validation {
      issuer        = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.api.id}"
      jwks_endpoint = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.api.id}/.well-known/jwks.json"
    }
  }

  # Action 2: Forward to target group if JWT is valid
  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# HTTP Listener - redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
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
    Project = "hello-fargate-webapi"
  }
}

# Outputs
output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.api.dns_name
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.api.arn
}

output "alb_url" {
  description = "The HTTPS URL of the ALB"
  value       = "https://${aws_lb.api.dns_name}"
}

output "target_group_arn" {
  description = "The ARN of the target group"
  value       = aws_lb_target_group.api.arn
}
