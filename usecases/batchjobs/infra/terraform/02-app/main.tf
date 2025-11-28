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

# NOTE: No ecs_cluster_arn variable - AWS Batch manages its own compute

variable "image_uri" {
  description = "The ECR image URI for the Batch job"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID for Batch compute environment networking"
  type        = string
}

variable "max_vcpus" {
  description = "Maximum vCPUs for compute environment"
  type        = number
  default     = 4
}

variable "job_vcpu" {
  description = "vCPUs per job (0.25, 0.5, 1, 2, 4)"
  type        = string
  default     = "0.25"
}

variable "job_memory" {
  description = "Memory per job in MiB"
  type        = number
  default     = 512
}

variable "security_group_ids" {
  description = "List of additional security group IDs"
  type        = list(string)
  default     = []
}
