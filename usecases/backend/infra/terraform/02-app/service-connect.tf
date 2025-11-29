# Service Connect Namespace (Cloud Map HTTP namespace)
resource "aws_service_discovery_http_namespace" "backend" {
  name        = "hello-fargate-backend.local"
  description = "Service Connect namespace for backend services"

  tags = {
    Project = "hello-fargate-backend"
  }
}

# Backend ECS Service with Service Connect (Server Mode)
resource "aws_ecs_service" "backend" {
  name            = "hello-fargate-backend-backend-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.vpc_subnets.ids
    security_groups  = concat([aws_security_group.backend_sg.id], var.security_group_ids)
    assign_public_ip = true
  }

  # Service Connect Configuration (Server Mode)
  # This registers the backend service in the namespace and makes it discoverable
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.backend.arn

    # Log configuration for Service Connect proxy (Envoy sidecar)
    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service_connect_logs.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "backend-sc"
      }
    }

    service {
      # port_name must match the container's portMappings.name
      port_name = "http"

      # Discovery name used by other services to connect
      discovery_name = "backend"

      client_alias {
        port     = 8080
        dns_name = "backend"
      }
    }
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Project = "hello-fargate-backend"
  }
}

# Frontend ECS Service with Service Connect (Client Mode)
resource "aws_ecs_service" "frontend" {
  name            = "hello-fargate-backend-frontend-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.vpc_subnets.ids
    security_groups  = concat([aws_security_group.frontend_sg.id], var.security_group_ids)
    assign_public_ip = true
  }

  # Service Connect Configuration (Client Mode)
  # Frontend joins the namespace and can resolve http://backend:8080
  # No service block = client mode only (doesn't register itself as discoverable)
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.backend.arn

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service_connect_logs.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "frontend-sc"
      }
    }
    # No service block = client mode only
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_service.backend
  ]

  tags = {
    Project = "hello-fargate-backend"
  }
}

# Outputs
output "namespace_arn" {
  description = "The ARN of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.backend.arn
}

output "namespace_name" {
  description = "The name of the Service Connect namespace"
  value       = aws_service_discovery_http_namespace.backend.name
}

output "backend_service_name" {
  description = "The name of the backend ECS service"
  value       = aws_ecs_service.backend.name
}

output "frontend_service_name" {
  description = "The name of the frontend ECS service"
  value       = aws_ecs_service.frontend.name
}

output "backend_discovery_name" {
  description = "The Service Connect discovery name for the backend"
  value       = "backend"
}

output "backend_endpoint" {
  description = "The Service Connect endpoint for the backend (used by frontend)"
  value       = "http://backend:8080"
}
