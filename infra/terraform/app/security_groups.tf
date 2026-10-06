# The ALB's security group: LoadBalancerSecurityGroup in app-ecs.yaml.

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb"
  description = "${var.app_name}-alb"
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

# The tasks' security group: ServiceSecurityGroup in app-ecs.yaml. Shared by
# frontend and backend; each task listens only on its own port.
resource "aws_security_group" "service" {
  name        = "${var.app_name}-service"
  description = "${var.app_name}-service"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

# 8080, not 80: the frontend image is nginx-unprivileged (non-root).
resource "aws_vpc_security_group_ingress_rule" "service_frontend" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "service_backend" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}

# Same strip as alb_all. Without it the tasks cannot pull their images, fetch
# the DB secret, ship logs, or reach RDS and Redis.
resource "aws_vpc_security_group_egress_rule" "service_all" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# The badge: RedisClientSecurityGroup in app-ecs.yaml. No rules at all.
# Wearing it is what redis_from_client admits on 6379. No egress either: a
# network interface gets the union of all its groups' rules, so the wearer's
# main group supplies outbound. CloudFormation kept AWS's allow-all here;
# dropped on purpose.
resource "aws_security_group" "redis_client" {
  name        = "${var.app_name}-redis-client"
  description = "${var.app_name}-redis-client (attach to anything that needs Redis)"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

# Redis's own group: RedisSecurityGroup in app-ecs.yaml. No password on
# Redis, so these two rules are the whole access boundary.
resource "aws_security_group" "redis" {
  name        = "${var.app_name}-redis"
  description = "${var.app_name}-redis"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_service" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.service.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_client" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.redis_client.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# No egress rule: Redis never opens a connection, it only replies, and
# statefulness lets replies out. CloudFormation kept AWS's allow-all here;
# dropped on purpose.
