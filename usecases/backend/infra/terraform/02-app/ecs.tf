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

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Security Groups
resource "aws_security_group" "backend_sg" {
  name        = "hello-fargate-backend-backend-sg"
  description = "Security group for backend service (internal only)"
  vpc_id      = var.vpc_id

  # Allow inbound on 8080 from VPC CIDR only (internal traffic via Service Connect)
  ingress {
    description = "HTTP from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "hello-fargate-backend"
  }
}

resource "aws_security_group" "frontend_sg" {
  name        = "hello-fargate-backend-frontend-sg"
  description = "Security group for frontend service (public for testing)"
  vpc_id      = var.vpc_id

  # Allow inbound on 8080 from anywhere (for testing)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 8080
    to_port     = 8080
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
    Project = "hello-fargate-backend"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend_logs" {
  name              = "/ecs/hello-fargate-backend-backend"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-backend"
  }
}

resource "aws_cloudwatch_log_group" "frontend_logs" {
  name              = "/ecs/hello-fargate-backend-frontend"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-backend"
  }
}

resource "aws_cloudwatch_log_group" "service_connect_logs" {
  name              = "/ecs/hello-fargate-backend-service-connect"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-backend"
  }
}

# IAM Roles
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "hello-fargate-backend-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-backend"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "hello-fargate-backend-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-backend"
  }
}

# Task Definitions
resource "aws_ecs_task_definition" "backend" {
  family                   = "hello-fargate-backend-backend-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-fargate-backend-backend"
      image     = var.backend_image_uri
      essential = true

      # Port mapping with name is REQUIRED for Service Connect
      portMappings = [
        {
          name          = "http"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = "8080"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project = "hello-fargate-backend"
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "hello-fargate-backend-frontend-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-fargate-backend-frontend"
      image     = var.frontend_image_uri
      essential = true

      # Port mapping with name for Service Connect
      portMappings = [
        {
          name          = "http"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = "8080"
        },
        {
          # Service Connect will resolve this hostname
          name  = "BACKEND_URL"
          value = "http://backend:8080"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project = "hello-fargate-backend"
  }
}

# Outputs
output "backend_task_definition_arn" {
  description = "The ARN of the backend task definition"
  value       = aws_ecs_task_definition.backend.arn
}

output "frontend_task_definition_arn" {
  description = "The ARN of the frontend task definition"
  value       = aws_ecs_task_definition.frontend.arn
}

output "backend_security_group_id" {
  description = "The ID of the backend security group"
  value       = aws_security_group.backend_sg.id
}

output "frontend_security_group_id" {
  description = "The ID of the frontend security group"
  value       = aws_security_group.frontend_sg.id
}

output "backend_log_group_name" {
  description = "The name of the backend CloudWatch log group"
  value       = aws_cloudwatch_log_group.backend_logs.name
}

output "frontend_log_group_name" {
  description = "The name of the frontend CloudWatch log group"
  value       = aws_cloudwatch_log_group.frontend_logs.name
}
