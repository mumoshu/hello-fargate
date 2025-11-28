data "aws_caller_identity" "current" {}

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
          "Cluster": "${var.ecs_cluster_arn}",
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
                "Cluster": "${var.ecs_cluster_arn}",
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

output "state_machine_arn" {
  description = "The ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.main.id
}
