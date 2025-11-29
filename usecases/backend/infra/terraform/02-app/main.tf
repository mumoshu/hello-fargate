terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

data "aws_region" "current" {}

# Variables
variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster to deploy to"
  type        = string
}

variable "backend_image_uri" {
  description = "The ECR image URI for the backend service"
  type        = string
}

variable "frontend_image_uri" {
  description = "The ECR image URI for the frontend service"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID for networking"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for ECS tasks"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MiB) for ECS tasks"
  type        = number
  default     = 512
}

variable "backend_desired_count" {
  description = "Desired count for backend service"
  type        = number
  default     = 2
}

variable "frontend_desired_count" {
  description = "Desired count for frontend service"
  type        = number
  default     = 1
}

variable "security_group_ids" {
  description = "Additional security group IDs to attach"
  type        = list(string)
  default     = []
}
