# Get subnets from the specified VPC
data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Security Group for Fargate tasks
resource "aws_security_group" "fargate_task_sg" {
  name        = "hello-fargate-backgroundjobs-task-sg"
  description = "Allow all outbound traffic for Fargate tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# CloudWatch Log Group for Fargate Task logs
resource "aws_cloudwatch_log_group" "task_logs" {
  name              = "/ecs/hello-fargate-backgroundjobs-task"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# --- IAM Roles for Fargate Task ---
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
  name               = "hello-fargate-backgroundjobs-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "hello-fargate-backgroundjobs-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# IAM Policy for SQS access
resource "aws_iam_role_policy" "task_sqs_policy" {
  name = "hello-fargate-backgroundjobs-sqs-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.jobs.arn
      }
    ]
  })
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "worker" {
  family                   = "hello-fargate-backgroundjobs-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-fargate-backgroundjobs-worker"
      image     = var.image_uri
      essential = true
      environment = [
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.jobs.url
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.task_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "ecs"
        }
      }
      portMappings = []
    }
  ])

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# --- ECS Service ---
resource "aws_ecs_service" "worker" {
  name            = "hello-fargate-backgroundjobs-service"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.vpc_subnets.ids
    security_groups  = concat([aws_security_group.fargate_task_sg.id], var.security_group_ids)
    assign_public_ip = true
  }

  # Allow service to be updated
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# --- ECS Outputs ---
output "task_definition_arn" {
  description = "The ARN of the ECS task definition"
  value       = aws_ecs_task_definition.worker.arn
}

output "task_definition_family" {
  description = "The family of the ECS task definition"
  value       = aws_ecs_task_definition.worker.family
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.worker.name
}

output "security_group_id" {
  description = "The ID of the security group for Fargate tasks"
  value       = aws_security_group.fargate_task_sg.id
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.task_logs.name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster (passed through)"
  value       = var.ecs_cluster_arn
}

output "container_name" {
  description = "The name of the container in the task definition"
  value       = "hello-fargate-backgroundjobs-worker"
}

output "subnet_ids" {
  description = "The subnet IDs discovered from the VPC"
  value       = data.aws_subnets.vpc_subnets.ids
}

output "vpc_id" {
  description = "The VPC ID used for networking"
  value       = var.vpc_id
}

output "task_role_arn" {
  description = "The ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "execution_role_arn" {
  description = "The ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}
