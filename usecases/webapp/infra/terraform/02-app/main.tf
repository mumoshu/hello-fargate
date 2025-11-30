terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {}

data "aws_region" "current" {}

# Random suffix for Cognito domain (must be globally unique)
resource "random_id" "suffix" {
  byte_length = 4
}

# Variables
variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster to deploy to"
  type        = string
}

variable "image_uri" {
  description = "The ECR image URI for the webapp service"
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

variable "desired_count" {
  description = "Desired count for webapp service"
  type        = number
  default     = 1
}

variable "security_group_ids" {
  description = "Additional security group IDs to attach"
  type        = list(string)
  default     = []
}

variable "internal" {
  description = "Whether ALB should be internal (for internal webapps)"
  type        = bool
  default     = false
}
