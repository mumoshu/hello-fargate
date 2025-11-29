terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

# ECR Repository for Backend service
resource "aws_ecr_repository" "backend" {
  name         = "hello-fargate-backend-backend"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "hello-fargate-backend"
  }
}

# ECR Repository for Frontend service
resource "aws_ecr_repository" "frontend" {
  name         = "hello-fargate-backend-frontend"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "hello-fargate-backend"
  }
}

output "backend_repository_url" {
  description = "The URL of the backend ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_repository_url" {
  description = "The URL of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}
