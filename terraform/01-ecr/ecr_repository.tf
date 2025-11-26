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
