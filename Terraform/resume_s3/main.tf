# Get account id
data "aws_caller_identity" "current" {}

locals {
  # use default policy if none provided
  bucket_policy = var.bucket_policy != "" ? var.bucket_policy : jsonencode(
{
        "Version": "2008-10-17",
        "Id": "PolicyForCloudFrontPrivateContent",
        "Statement": [
            {
                "Sid": "AllowCloudFrontServicePrincipal",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudfront.amazonaws.com"
                },
                "Action": "s3:GetObject",
                "Resource": [
                  "arn:aws:s3:::${var.bucket_name}",
                  "arn:aws:s3:::${var.bucket_name}/*"
                ],
                "Condition": {
                    "StringEquals": {
                      "AWS:SourceArn": "${var.cfn_arn}"
                    }
                }
            }
        ]
      })
}


resource "aws_s3_bucket" "resumeS3" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.resumeS3.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_acl" "default" {
  bucket = aws_s3_bucket.resumeS3.id
  acl    = "private"
  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_ownership]
}

# Resource to avoid error "AccessControlListNotSupported: The bucket does not allow ACLs"
resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_ownership" {
  bucket = aws_s3_bucket.resumeS3.id
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.resumeS3.id
  policy = local.bucket_policy
}