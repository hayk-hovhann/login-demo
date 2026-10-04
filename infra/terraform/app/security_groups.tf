# The ALB's security group: LoadBalancerSecurityGroup in app-ecs.yaml.

resource "aws_security_group" "alb" {
  name        = "login-demo-app-alb"
  description = "login-demo-app-alb"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

# Rules are separate resources, not inline ingress blocks: the provider's
# current best practice. Never mix the two on one group, or they overwrite
# each other.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# 443 exists only when a certificate is supplied: HasCertificate in
# app-ecs.yaml. Port 80 stays open either way; with TLS on, it serves the
# 301 to HTTPS.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.certificate_arn == null ? 0 : 1

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# AWS gives every new group an allow-all egress rule. CloudFormation kept it;
# Terraform strips it on create. Restated here, or the ALB cannot open
# connections to the tasks.
resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
