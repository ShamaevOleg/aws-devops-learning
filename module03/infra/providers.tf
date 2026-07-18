# providers.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = "~> 1.15.1"
  backend "s3" {
    bucket       = "oleg-tfstate-initial"
    key          = "module02/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # нативная блокировка в S3, без DynamoDB
  }
}

provider "aws" {
  region = "eu-west-2"
  default_tags {
    tags = {
      Project   = "aws-devops-learning"
      ManagedBy = "terraform"
    }
  }
}