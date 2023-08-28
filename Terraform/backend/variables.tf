variable "domain_name" {
  type = string
  description = "The domain name to be used with Cloud Front."
}

variable "s3_bucket_lambda_package" {
  type = string
}