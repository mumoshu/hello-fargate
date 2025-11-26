variable "image_uri" {
  description = "The ECR image URI for the Fargate task (Generated from AWS_ACCOUNT_ID, AWS_REGION env vars)"
  type        = string
}

variable "task_cpu" {
  description = "Fargate task CPU units (e.g., 256, 512, 1024) (Optional, set via TF_TASK_CPU env var)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB (e.g., 512, 1024, 2048) (Optional, set via TF_TASK_MEMORY env var)"
  type        = number
  default     = 512
}
variable "subnet_ids" {
  description = "List of subnet IDs for Fargate task networking (Set via TF_SUBNET_IDS env var, comma-separated)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of *additional* security group IDs (Optional, set via TF_EXTRA_SG_IDS env var, comma-separated)"
  type        = list(string)
  default     = []
}

data "aws_vpc" "default" {
  default = true
}

# Security Group for Fargate tasks
resource "aws_security_group" "fargate_task_sg" {
  name        = "${var.prefix}-task-sg"
  description = "Allow all outbound traffic for Fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.prefix
  }
}

# ECS Cluster to host Fargate tasks
resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project = var.prefix
  }
}

# CloudWatch Log Group for Fargate Task logs
resource "aws_cloudwatch_log_group" "task_logs" {
  name = "/ecs/${var.prefix}-task"

  retention_in_days = 30

  tags = {
    Project = var.prefix
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
  name               = "${var.prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = var.prefix
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags = {
    Project = var.prefix
  }
}

# Policy allowing the task role to send status back to Step Functions
data "aws_iam_policy_document" "ecs_task_sfn_callback_policy" {
  statement {
    actions = [
      "states:SendTaskSuccess",
      "states:SendTaskFailure",
      "states:SendTaskHeartbeat" // Optional but good practice
    ]
    resources = ["*"] // Best practice: Scope this down if possible, e.g., to the specific state machine ARN if known/passed
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "ecs_task_sfn_callback" {
  name        = "${var.prefix}-ecs-task-sfn-callback-policy"
  description = "Allow ECS tasks to send success/failure back to Step Functions"
  policy      = data.aws_iam_policy_document.ecs_task_sfn_callback_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_sfn_callback_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_sfn_callback.arn
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "app_task" {
  family                   = "${var.prefix}-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.prefix}-app-container"
      image     = var.image_uri # This is now a required input variable for this module
      essential = true
      environment = [
        {
          name  = "TASK_INPUT",
          value = "{}" // Default, will be overridden by SFN
        },
        // Definition for SFN Task Token - Value injected by SFN
        {
          name  = "AWS_STEP_FUNCTIONS_TASK_TOKEN",
          value = "dummy" // Placeholder, will be overridden by SFN 
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.task_logs.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      portMappings = []
    }
  ])

  tags = {
    Project = var.prefix
  }
}

output "fargate_task_security_group_id" {
  description = "The ID of the security group created for the Fargate tasks"
  value       = aws_security_group.fargate_task_sg.id
}
