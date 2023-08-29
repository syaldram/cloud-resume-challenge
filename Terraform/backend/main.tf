data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

    lambda_function_association {
      event_type   = "viewer-response"
      lambda_arn   = module.update_viewer_count.lambda_function_qualified_arn
      include_body = false
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

################################################################################
# Lambda function to update dynamoDB table before CloudFront returns a response
################################################################################

module "update_viewer_count" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "6.0.0"

  function_name  = "update_viewer_count"
  description    = "Updates viewer count DynamoDB table before CloudFront returns a response."
  handler        = "index.lambda_handler"
  runtime        = "python3.10"
  create_package = true
  timeout        = 5
  memory_size    = 128
  publish        = true

  source_path    = "${path.module}/post_views/"

  build_in_docker          = true
  docker_build_root        = "${path.module}/post_views/docker"
  docker_image             = "public.ecr.aws/lambda/python:3.10"
  store_on_s3              = true
  s3_bucket                = var.s3_bucket_lambda_package
  recreate_missing_package = true

  create_role = false
  lambda_role = aws_iam_role.update_viewer_count.arn

}

################################################################################
# IAM role to update_viewer_count Lambda
################################################################################

resource "aws_iam_role" "update_viewer_count" {
  name                 = "update_viewer_count"
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
          },
          "Effect" : "Allow",
          }, {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "AWS" : [
            data.aws_caller_identity.current.account_id]
          },
          "Effect" : "Allow",
        }
      ]
  })
}

resource "aws_iam_role_policy" "update_viewer_count" {
  name = "update_viewer_count"
  role = aws_iam_role.update_viewer_count.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ],
        Effect = "Allow",
        Resource = "${aws_dynamodb_table.counter-db.arn}"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      },
    ]
  })
}

################################################################################
# Lambda function to get viewer count from DynamoDB & send data to API Gateway
################################################################################

module "get_viewer_count" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "6.0.0"

  function_name  = "get_viewer_count"
  description    = "Get viewer count from DynamoDB table & send data to API Gateway."
  handler        = "index.lambda_handler"
  runtime        = "python3.10"
  create_package = true
  timeout        = 30
  memory_size    = 128
  publish        = true

  source_path    = "${path.module}/get_views/"

  build_in_docker          = true
  docker_build_root        = "${path.module}/get_views/docker"
  docker_image             = "public.ecr.aws/lambda/python:3.10"
  store_on_s3              = true
  s3_bucket                = var.s3_bucket_lambda_package
  recreate_missing_package = true

  create_role = false
  lambda_role = aws_iam_role.get_viewer_count.arn

}

################################################################################
# IAM role to get_viewer_count Lambda
################################################################################

resource "aws_iam_role" "get_viewer_count" {
  name                 = "get_viewer_count"
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "lambda.amazonaws.com"
          },
          "Effect" : "Allow",
          }, {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "AWS" : [
            data.aws_caller_identity.current.account_id]
          },
          "Effect" : "Allow",
        }
      ]
  })
}

resource "aws_iam_role_policy" "get_viewer_count" {
  name = "get_viewer_count"
  role = aws_iam_role.get_viewer_count.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem"
        ],
        Effect = "Allow",
        Resource = "${aws_dynamodb_table.counter-db.arn}"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      },
    ]
  })
}

################################################################################
# Create API Gateway for get_viewer data from web application
################################################################################

resource "aws_api_gateway_rest_api" "get_views_api" {
  name        = "get_views_api"
  description = "REST API with lambda integration to get dynamoDB data for web application."
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.get_views_api.id
  parent_id   = aws_api_gateway_rest_api.get_views_api.root_resource_id
  path_part   = "counter"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.get_views_api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "api_integration" {
  rest_api_id             = aws_api_gateway_rest_api.get_views_api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = module.get_viewer_count.lambda_function_invoke_arn
}

resource "aws_cloudwatch_log_group" "api_log_group" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.get_views_api.name}"
  retention_in_days = 14
}

resource "aws_iam_role" "api_role" {
  name               = "${aws_api_gateway_rest_api.get_views_api.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_policy_attachment" {
  role       = aws_iam_role.api_role.name
  policy_arn = aws_iam_policy.api_policy.arn
}

resource "aws_iam_policy" "api_policy" {
  name        = "${aws_iam_role.api_role.name}-policy"
  description = "${aws_iam_role.api_role.name} policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id       = aws_api_gateway_rest_api.get_views_api.id
  stage_name        = "prod"
  depends_on        = [aws_api_gateway_integration.api_integration]
}

resource "aws_lambda_permission" "api_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.get_viewer_count.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  source_arn    = "${aws_api_gateway_rest_api.get_views_api.execution_arn}/*"
}

resource "aws_api_gateway_method_response" "cors_method_response" {
  rest_api_id = aws_api_gateway_rest_api.get_views_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "cors_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.get_views_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = aws_api_gateway_method_response.cors_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}
