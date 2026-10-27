# The ALB's security group.

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb"
  description = "${var.app_name}-alb"
  vpc_id      = local.network.vpc_id
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

# 443 exists only when a certificate is supplied (local.tls). Port 80 stays
# open either way; with TLS on, it serves the 301 to HTTPS.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = local.tls ? 1 : 0

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

# The tasks' security group, shared by frontend and backend; each task listens
# only on its own port.
resource "aws_security_group" "service" {
  name        = "${var.app_name}-service"
  description = "${var.app_name}-service"
  vpc_id      = local.network.vpc_id
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

# The migration task's main group, worn beside the data layer's DB badge. The
# badge carries no egress, so without this the task has no outbound at all and
# dies fetching the DB secret. No ingress: a one-shot task accepts nothing.
resource "aws_security_group" "migrate" {
  name        = "${var.app_name}-migrate"
  description = "${var.app_name}-migrate (one-shot migration task; outbound only)"
  vpc_id      = local.network.vpc_id
}

# Same strip as service_all: ECR, Secrets Manager, CloudWatch Logs and RDS.
resource "aws_vpc_security_group_egress_rule" "migrate_all" {
  security_group_id = aws_security_group.migrate.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# The badge: no rules at all. Wearing it is what redis_from_client admits on
# 6379. No egress either: a network interface gets the union of all its
# groups' rules, so the wearer's main group supplies outbound. CloudFormation
# kept AWS's allow-all here; dropped on purpose.
resource "aws_security_group" "redis_client" {
  name        = "${var.app_name}-redis-client"
  description = "${var.app_name}-redis-client (attach to anything that needs Redis)"
  vpc_id      = local.network.vpc_id
}

# Redis's own group. No password on Redis, so these two rules are the whole
# access boundary.
resource "aws_security_group" "redis" {
  name        = "${var.app_name}-redis"
  description = "${var.app_name}-redis"
  vpc_id      = local.network.vpc_id
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
