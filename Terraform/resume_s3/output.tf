output "name" {
  value       = aws_s3_bucket.resumeS3.id
  description = "The name of the bucket"
}

output "arn" {
  value       = aws_s3_bucket.resumeS3.arn
  description = "The ARN of the bucket"
}

output "domain_name" {
  value = aws_s3_bucket.resumeS3.bucket_regional_domain_name
}