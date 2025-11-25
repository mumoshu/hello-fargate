terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_region" "current" {
  provider = aws
}

variable "prefix" {
  description = "A prefix for resource names to ensure uniqueness (Optional, set via TF_PREFIX env var)"
  type        = string
  default     = "fargate-workflow"
}

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

variable "schedule_expression" {
  description = "EventBridge schedule expression (Optional, set via TF_SCHEDULE env var)"
  type        = string
  default     = "rate(1 hour)"
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

# --- Data Sources ---
data "aws_vpc" "default" {
  default = true
}

data "aws_caller_identity" "current" {}

# --- AWS Resources ---

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

# --- IAM Roles for Step Functions & EventBridge ---
data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_role" {
  name               = "${var.prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json

  tags = {
    Project = var.prefix
  }
}

data "aws_iam_policy_document" "sfn_policy" {
  statement {
    actions = [
      "ecs:RunTask"
    ]
    resources = [
      // Allow running any version of the task definition matching the prefix
      "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.prefix}-app-task:*"
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.ecs_task_execution_role.arn,
      aws_iam_role.ecs_task_role.arn
    ]
    effect = "Allow"
  }
  statement {
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"
    ]
    resources = ["arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "sfn_role_policy" {
  name   = "${var.prefix}-sfn-policy"
  role   = aws_iam_role.sfn_role.id
  policy = data.aws_iam_policy_document.sfn_policy.json
}

data "aws_iam_policy_document" "events_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "event_bridge_role" {
  name               = "${var.prefix}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json

  tags = {
    Project = var.prefix
  }
}

data "aws_iam_policy_document" "event_bridge_policy" {
  statement {
    actions   = ["states:StartExecution"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "event_bridge_role_policy" {
  name   = "${var.prefix}-eventbridge-policy"
  role   = aws_iam_role.event_bridge_role.id
  policy = data.aws_iam_policy_document.event_bridge_policy.json
}

# --- Step Functions State Machine ---
resource "aws_sfn_state_machine" "main" {
  name     = "${var.prefix}-main-workflow"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<-EOF
  {
    "Comment": "Workflow with initial step followed by parallel Fargate tasks",
    "StartAt": "InitialStep",
    "States": {
      "InitialStep": {
        "Type": "Task",
        "Resource": "arn:aws:states:::ecs:runTask.waitForTaskToken",
        "Parameters": {
          "LaunchType": "FARGATE",
          "Cluster": "${aws_ecs_cluster.main.arn}",
          "TaskDefinition": "${aws_ecs_task_definition.app_task.arn}",
          "NetworkConfiguration": {
            "AwsvpcConfiguration": {
              "Subnets": ${jsonencode(var.subnet_ids)},
              "SecurityGroups": ${jsonencode(concat([aws_security_group.fargate_task_sg.id], var.security_group_ids))},
              "AssignPublicIp": "ENABLED"
            }
          },
          "Overrides": {
            "ContainerOverrides": [
              {
                "Name": "${var.prefix}-app-container",
                "Environment": [
                  { "Name": "TASK_INPUT", "Value.$": "States.JsonToString($)" },
                  { "Name": "AWS_STEP_FUNCTIONS_TASK_TOKEN", "Value.$": "$$.Task.Token" }
                ]
              }
            ]
          }
        },
        "ResultPath": "$.initialTaskOutput",
        "Next": "ParallelSteps"
      },
      "ParallelSteps": {
        "Type": "Map",
        "ItemsPath": "$.initialTaskOutput.parallelItems",
        "ResultPath": "$.parallelResults",
        "MaxConcurrency": 5,
        "Iterator": {
          "StartAt": "RunParallelTask",
          "States": {
            "RunParallelTask": {
              "Type": "Task",
              "Resource": "arn:aws:states:::ecs:runTask.waitForTaskToken",
              "Parameters": {
                "LaunchType": "FARGATE",
                "Cluster": "${aws_ecs_cluster.main.arn}",
                "TaskDefinition": "${aws_ecs_task_definition.app_task.arn}",
                "NetworkConfiguration": {
                  "AwsvpcConfiguration": {
                    "Subnets": ${jsonencode(var.subnet_ids)},
                    "SecurityGroups": ${jsonencode(concat([aws_security_group.fargate_task_sg.id], var.security_group_ids))},
                    "AssignPublicIp": "ENABLED"
                  }
                },
                "Overrides": {
                  "ContainerOverrides": [
                    {
                      "Name": "${var.prefix}-app-container",
                      "Environment": [
                        { "Name": "TASK_INPUT", "Value.$": "States.JsonToString($)" },
                        { "Name": "AWS_STEP_FUNCTIONS_TASK_TOKEN", "Value.$": "$$.Task.Token" }
                      ]
                    }
                  ]
                }
              },
              "ResultPath": "$.x",
              "End": true
            }
          }
        },
        "Next": "WorkflowSucceed"
      },
      "WorkflowSucceed": {
        "Type": "Succeed"
      }
    }
  }
  EOF

  tags = {
    Project = var.prefix
  }
}

# --- EventBridge Schedule ---
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.prefix}-schedule-rule"
  description         = "Triggers the ${var.prefix} Step Function periodically"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"

  tags = {
    Project = var.prefix
  }
}

resource "aws_cloudwatch_event_target" "sfn_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "${var.prefix}-sfn-target"
  arn       = aws_sfn_state_machine.main.id
  role_arn  = aws_iam_role.event_bridge_role.arn
}

# --- Update EventBridge Policy to target specific State Machine ---
resource "aws_iam_role_policy" "event_bridge_role_policy_updated" {
  name = "${var.prefix}-eventbridge-policy"
  role = aws_iam_role.event_bridge_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["states:StartExecution"]
        Effect   = "Allow"
        Resource = [aws_sfn_state_machine.main.id]
      },
    ]
  })
  depends_on = [aws_sfn_state_machine.main]
}

# --- Test EventBridge Rule for Manual Triggering ---
resource "aws_cloudwatch_event_rule" "test_trigger" {
  name        = "${var.prefix}-test-trigger-rule"
  description = "Test rule for manually triggering the ${var.prefix} Step Function"
  
  event_pattern = jsonencode({
    source = ["fargate.workflow.test"]
    detail-type = ["Test Trigger"]
  })

  tags = {
    Project = var.prefix
    Purpose = "Testing"
  }
}

resource "aws_cloudwatch_event_target" "test_sfn_target" {
  rule      = aws_cloudwatch_event_rule.test_trigger.name
  target_id = "${var.prefix}-test-sfn-target"
  arn       = aws_sfn_state_machine.main.id
  role_arn  = aws_iam_role.event_bridge_role.arn
  
  # Pass the event detail as input to the state machine
  input_transformer {
    input_paths = {
      detail = "$.detail"
    }
    input_template = <<EOF
{
  "testTriggered": true,
  "eventDetail": <detail>
}
EOF
  }
}

# --- Outputs ---
output "state_machine_arn" {
  description = "The ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.main.id
}

output "event_bus_name" {
  description = "The name of the EventBridge event bus (default)"
  value       = "default"
}

output "test_event_rule_name" {
  description = "The name of the test EventBridge rule"
  value       = aws_cloudwatch_event_rule.test_trigger.name
}

output "fargate_task_security_group_id" {
  description = "The ID of the security group created for the Fargate tasks"
  value       = aws_security_group.fargate_task_sg.id
}
