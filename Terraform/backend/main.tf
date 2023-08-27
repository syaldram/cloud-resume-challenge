data "aws_caller_identity" "current" {}

locals {
  s3_origin_id = "SyBucketOrigin"
  root_domain_name = "saadyaldram.com"
  cv_domain_name = "resume.${local.root_domain_name}"
}

################################################################################
# Create a cloud front CDN 
################################################################################

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = var.domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_originAc.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Saad Yaldram's personal website frontend."
  default_root_object = "index.html"

  aliases = [local.cv_domain_name]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    compress         = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = module.acm.acm_certificate_arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_cloudfront_origin_access_control" "s3_originAc" {
  name                              = "SyOriginAc"
  description                       = "Policy for S3 origin access control"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

################################################################################
# Create Route53 DNS
################################################################################

data "aws_route53_zone" "zone" {
  name         = local.root_domain_name
  private_zone = false
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.cv_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

################################################################################
# Create SSL/TLS certificate.
################################################################################

module "acm" {

  #Terraform module which creates ACM certificates and validates them using Route53 DNS
  source  = "terraform-aws-modules/acm/aws"
  version = "4.3.2"

  domain_name  = "*.${local.root_domain_name}"
  zone_id      = data.aws_route53_zone.zone.zone_id

  subject_alternative_names = ["${local.root_domain_name}"]
  wait_for_validation = true

}

################################################################################
# Create DynamoDB database to track visitor count
################################################################################

resource "aws_dynamodb_table" "counter-db" {
  name         = "crc-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "CounterID"
  attribute {
    name = "CounterID"
    type = "S"
  }
}