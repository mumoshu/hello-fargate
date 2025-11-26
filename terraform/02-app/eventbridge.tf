
variable "schedule_expression" {
  description = "EventBridge schedule expression (Optional, set via TF_SCHEDULE env var)"
  type        = string
  default     = "rate(1 hour)"
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

output "event_bus_name" {
  description = "The name of the EventBridge event bus (default)"
  value       = "default"
}

output "test_event_rule_name" {
  description = "The name of the test EventBridge rule"
  value       = aws_cloudwatch_event_rule.test_trigger.name
}
