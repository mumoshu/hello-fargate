data "aws_vpc" "default" {
  default = true
}

# Security Group for Fargate tasks
resource "aws_security_group" "fargate_task_sg" {
  name        = "hello-fargate-oneoff-task-sg"
  description = "Allow all outbound traffic for Fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "hello-fargate-oneoff"
  }
}

# CloudWatch Log Group for Fargate Task logs
resource "aws_cloudwatch_log_group" "task_logs" {
  name              = "/ecs/hello-fargate-oneoff-task"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-oneoff"
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
  name               = "hello-fargate-oneoff-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-oneoff"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "hello-fargate-oneoff-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = "hello-fargate-oneoff"
  }
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "app_task" {
  family                   = "hello-fargate-oneoff-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-fargate-oneoff-app-container"
      image     = var.image_uri
      essential = true
      environment = [
        {
          name  = "TASK_INPUT",
          value = "{}"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.task_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      portMappings = []
    }
  ])

  tags = {
    Project = "hello-fargate-oneoff"
  }
}

# --- Outputs ---
output "task_definition_arn" {
  description = "The ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app_task.arn
}

output "task_definition_family" {
  description = "The family of the ECS task definition"
  value       = aws_ecs_task_definition.app_task.family
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
  value       = "hello-fargate-oneoff-app-container"
}

output "subnet_ids" {
  description = "The subnet IDs used for networking (passed through)"
  value       = var.subnet_ids
}
