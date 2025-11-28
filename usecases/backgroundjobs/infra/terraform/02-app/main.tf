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

data "aws_region" "current" {}

variable "ecs_cluster_arn" {
  description = "The ARN of the shared ECS cluster"
  type        = string
}

variable "image_uri" {
  description = "The ECR image URI for the Fargate task"
  type        = string
}

variable "task_cpu" {
  description = "Fargate task CPU units (e.g., 256, 512, 1024)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB (e.g., 512, 1024, 2048)"
  type        = number
  default     = 512
}

variable "vpc_id" {
  description = "The VPC ID for Fargate task networking"
  type        = string
}

variable "security_group_ids" {
  description = "List of additional security group IDs"
  type        = list(string)
  default     = []
}

variable "desired_count" {
  description = "Desired number of worker instances"
  type        = number
  default     = 1
}
