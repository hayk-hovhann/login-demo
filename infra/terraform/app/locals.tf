# HasCertificate in app-ecs.yaml: a certificate turns TLS on. Read by both
# listeners and the alb group's 443 rule.
locals {
  tls = var.certificate_arn != null
}
