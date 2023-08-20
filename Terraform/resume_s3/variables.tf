variable "bucket_name" {
  type        = string
  description = "The name of the bucket"
}

variable "versioning" {
  type        = bool
  default     = true
  description = "Enable versioning on the bucket, defaults to true"
}

variable "bucket_policy" {
  type        = string
  default     = ""
  description = "The bucket policy to apply to the bucket, defaults to a policy that only allows SSL requests"
}

variable "cfn_arn" {
  type = string
  description = "ARN for cloud front distriubtion."
}