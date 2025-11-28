# Dead Letter Queue for failed messages
resource "aws_sqs_queue" "dlq" {
  name                      = "hello-fargate-backgroundjobs-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# Main Queue for job messages
resource "aws_sqs_queue" "jobs" {
  name                       = "hello-fargate-backgroundjobs-queue"
  visibility_timeout_seconds = 300 # 5 minutes
  receive_wait_time_seconds  = 20  # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Project = "hello-fargate-backgroundjobs"
  }
}

# --- SQS Outputs ---
output "queue_url" {
  description = "The URL of the SQS queue"
  value       = aws_sqs_queue.jobs.url
}

output "queue_arn" {
  description = "The ARN of the SQS queue"
  value       = aws_sqs_queue.jobs.arn
}

output "queue_name" {
  description = "The name of the SQS queue"
  value       = aws_sqs_queue.jobs.name
}

output "dlq_url" {
  description = "The URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "The ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}
