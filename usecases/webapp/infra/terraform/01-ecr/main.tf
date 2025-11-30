terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

# ECR Repository for Webapp service
resource "aws_ecr_repository" "webapp" {
  name         = "hello-fargate-webapp-app"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "hello-fargate-webapp"
  }
}

output "repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.webapp.repository_url
}
