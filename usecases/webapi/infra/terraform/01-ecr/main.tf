terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

# ECR Repository for WebAPI service
resource "aws_ecr_repository" "api" {
  name         = "hello-fargate-webapi-app"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "hello-fargate-webapi"
  }
}

output "repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.api.repository_url
}
