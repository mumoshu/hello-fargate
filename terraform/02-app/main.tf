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

data "aws_region" "current" {
  provider = aws
}

variable "prefix" {
  description = "A prefix for resource names to ensure uniqueness (Optional, set via TF_PREFIX env var)"
  type        = string
  default     = "fargate-workflow"
}
