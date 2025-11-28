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

variable "prefix" {
  description = "A prefix for resource names to ensure uniqueness (Optional, set via TF_PREFIX env var)"
  type        = string
  default     = "fargate-workflow"
}

# ECR Repository to store the application image
resource "aws_ecr_repository" "app" {
  name = "${var.prefix}-app" # e.g., fargate-workflow-app

  image_tag_mutability = "MUTABLE" # Or "IMMUTABLE" if you prefer
  force_delete         = true      # Allows deletion even if images exist

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.prefix
  }
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}
