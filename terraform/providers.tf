terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure a remote backend before using this beyond solo learning.
  # backend "s3" {
  #   bucket = "my-terraform-state-bucket"
  #   key    = "eks-gitops/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region
}
