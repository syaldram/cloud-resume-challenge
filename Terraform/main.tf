terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "> 4.0"
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
  backend "s3" {
    bucket         = "terraform-backend-sy"
    key            = "cloud-resume-challenge.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "cloud-resume-challenge"
      Provisioned = "Terraform"
      Owner       = "Saad Yaldram"
    }
  }
}

module "resume_s3" {
  source      = "./resume_s3"
  bucket_name = var.bucket_name
  cfn_arn     = module.backend.cfn_arn
}

module "backend" {
  source                   = "./backend"
  domain_name              = module.resume_s3.domain_name
  s3_bucket_lambda_package = var.s3_bucket_lambda_package
}
