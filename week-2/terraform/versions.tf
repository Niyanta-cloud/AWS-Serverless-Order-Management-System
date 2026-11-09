# PROVIDER REQUIREMENTS
# Tell Terraform which providers (AWS and archive) this configuration needs.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# AWS PROVIDER
# Connect Terraform to AWS in the selected region using the local AWS CLI profile.
# The profile supplies credentials; do not put access keys in this file.
provider "aws" {
  region  = var.aws_region
  profile = "orderflow"
}
