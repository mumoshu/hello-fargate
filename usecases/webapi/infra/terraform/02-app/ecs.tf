# ECS Service for WebAPI

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# ECS Security Group (allow traffic from ALB only)
resource "aws_security_group" "ecs_sg" {
  name        = "hello-fargate-webapi-ecs-sg"
  description = "Security group for WebAPI ECS tasks"
  vpc_id      = var.vpc_id

  # Allow inbound from ALB only
  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
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

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/ecs/hello-fargate-webapi"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-webapi"
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
  name               = "hello-fargate-webapi-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-webapi"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "hello-fargate-webapi-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "api" {
  family                   = "hello-fargate-webapi-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-fargate-webapi-container"
      image     = var.image_uri
      essential = true

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
          "awslogs-group"         = aws_cloudwatch_log_group.api_logs.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# ECS Service with ALB integration
resource "aws_ecs_service" "api" {
  name            = "hello-fargate-webapi-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.vpc_subnets.ids
    security_groups  = concat([aws_security_group.ecs_sg.id], var.security_group_ids)
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "hello-fargate-webapi-container"
    container_port   = 8080
  }

  # Wait for ALB listener to be ready
  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# Outputs
output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.api.name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = var.ecs_cluster_arn
}

output "task_definition_arn" {
  description = "The ARN of the task definition"
  value       = aws_ecs_task_definition.api.arn
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_logs.name
}
