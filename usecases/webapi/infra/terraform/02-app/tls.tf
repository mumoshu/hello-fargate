# Self-signed TLS certificate for ALB HTTPS listener
# This allows us to use HTTPS without Route53/ACM validation

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "api.webapi.local"
    organization = "Hello Fargate WebAPI"
  }

  # Valid for 1 year
  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  # Also valid for the ALB DNS name
  dns_names = [
    "api.webapi.local",
    "*.elb.amazonaws.com",
    "*.elb.${data.aws_region.current.region}.amazonaws.com",
  ]
}

# Import the self-signed certificate into ACM
resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Project = "hello-fargate-webapi"
  }
}

# Outputs
output "certificate_arn" {
  description = "The ARN of the ACM certificate"
  value       = aws_acm_certificate.alb.arn
}

output "certificate_domain" {
  description = "The domain name of the certificate"
  value       = tls_self_signed_cert.alb.subject[0].common_name
}
