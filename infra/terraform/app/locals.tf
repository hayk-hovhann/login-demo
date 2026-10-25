# A certificate turns TLS on. Read by both listeners, the alb group's 443 rule,
# the backend's COOKIE_SECURE and the url output.
locals {
  tls = var.certificate_arn != null
}
