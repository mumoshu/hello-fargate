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

# Security Group - outbound only (same pattern as other use cases)
resource "aws_security_group" "batch_sg" {
  name        = "hello-fargate-batchjobs-batch-sg"
  description = "Security group for Batch jobs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "batch_logs" {
  name              = "/aws/batch/hello-fargate-batchjobs"
  retention_in_days = 30

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

# Compute Environment - Fargate On-Demand
# NOTE: By omitting service_role, AWS Batch automatically uses the service-linked role
# "AWSServiceRoleForBatch" (arn:aws:iam::ACCOUNT:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch)
# which has the latest permissions for Fargate. Using a custom service role with
# AWSBatchServiceRole policy may cause jobs to get stuck in RUNNABLE state.
resource "aws_batch_compute_environment" "fargate" {
  name  = "hello-fargate-batchjobs-compute-env"
  type  = "MANAGED"
  state = "ENABLED"
  # service_role is intentionally omitted - AWS Batch will use AWSServiceRoleForBatch

  compute_resources {
    type = "FARGATE"
    # To use Fargate Spot (up to 70% cost savings), change to:
    # type = "FARGATE_SPOT"
    max_vcpus          = var.max_vcpus
    security_group_ids = concat([aws_security_group.batch_sg.id], var.security_group_ids)
    subnets            = data.aws_subnets.vpc_subnets.ids
  }

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

# Job Queue
resource "aws_batch_job_queue" "main" {
  name     = "hello-fargate-batchjobs-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.fargate.arn
  }

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

# Job Definition
resource "aws_batch_job_definition" "worker" {
  name                  = "hello-fargate-batchjobs-job-def"
  type                  = "container"
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = var.image_uri

    resourceRequirements = [
      { type = "VCPU", value = var.job_vcpu },
      { type = "MEMORY", value = tostring(var.job_memory) }
    ]

    executionRoleArn = aws_iam_role.batch_execution_role.arn
    # jobRoleArn = aws_iam_role.batch_job_role.arn  # Uncomment if app needs AWS API access

    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }

    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "batch"
      }
    }

    # Default environment - can be overridden at job submission
    environment = [
      { name = "JOB_INPUT", value = "{}" }
    ]
  })

  tags = {
    Project = "hello-fargate-batchjobs"
  }
}

# Outputs
output "job_queue_arn" {
  description = "The ARN of the Batch job queue"
  value       = aws_batch_job_queue.main.arn
}

output "job_queue_name" {
  description = "The name of the Batch job queue"
  value       = aws_batch_job_queue.main.name
}

output "job_definition_arn" {
  description = "The ARN of the Batch job definition"
  value       = aws_batch_job_definition.worker.arn
}

output "job_definition_name" {
  description = "The name of the Batch job definition"
  value       = aws_batch_job_definition.worker.name
}

output "compute_environment_arn" {
  description = "The ARN of the compute environment"
  value       = aws_batch_compute_environment.fargate.arn
}

output "log_group_name" {
  description = "CloudWatch log group for batch jobs"
  value       = aws_cloudwatch_log_group.batch_logs.name
}

output "security_group_id" {
  description = "Security group ID for batch jobs"
  value       = aws_security_group.batch_sg.id
}
