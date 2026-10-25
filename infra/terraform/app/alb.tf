# The load balancer. AWS runs its nodes in both subnets, each one an ENI
# wearing the alb group, and one DNS name fronts them all. Use the name, never
# the IPs: they change as AWS replaces nodes. Bills from creation,
# ~$0.0225/hr, with or without traffic, and accepts nothing until a listener
# exists.
resource "aws_lb" "main" {
  name               = var.app_name
  load_balancer_type = "application"

  # Internet-facing: public IPs on the nodes, a DNS name that resolves publicly.
  internal        = false
  ip_address_type = "ipv4"

  security_groups = [aws_security_group.alb.id]

  # An ALB needs at least two availability zones: one subnet in each.
  subnets = [
    data.aws_cloudformation_export.subnet_a_id.value,
    data.aws_cloudformation_export.subnet_b_id.value,
  ]
}

# Target groups: where the ALB sends a request once a rule has picked a
# service, and how it health-checks each destination. Created empty: each ECS
# service registers its tasks' IPs as they start. Free, and inert until a
# listener uses one; with no load balancer, nothing probes.
#
# A map rather than logs.tf's set, because the two differ: each.value carries
# the name prefix, the port and the health check path.
# aws_lb_target_group.main["backend"].
resource "aws_lb_target_group" "main" {
  for_each = {
    # 8080, the unprivileged nginx port. nginx serves index.html, so / is a 200.
    frontend = { name_prefix = "front-", port = 8080, health_check_path = "/" }

    # Liveness only, and never touches Postgres, so tasks go healthy before the
    # migration has run. Not /api/auth/me: anonymous, it returns 403, outside
    # the matcher, so no task could ever go healthy.
    backend = { name_prefix = "back-", port = 3000, health_check_path = "/api/health" }
  }

  # A prefix, not a name: the provider appends a 26-character unique ID at every
  # create, so a replacement never collides with the group it replaces (names
  # are unique per region per account). AWS caps the whole name at 32, which
  # leaves the prefix 6. Nothing reads the name: the alarms and the dashboard
  # use arn_suffix, the listener, the rule and ecs.tf use arn.
  name_prefix = each.value.name_prefix

  vpc_id   = data.aws_cloudformation_export.vpc_id.value
  port     = each.value.port
  protocol = "HTTP"

  # Fargate tasks have no instance to register; each registers by its ENI's IP.
  target_type = "ip"

  # How long a stopping task gets to finish in-flight requests. The default is
  # 300, which can hold every deploy open five minutes while old tasks drain.
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    interval            = 15
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  # LOAD-BEARING on any change that forces a replacement: port, protocol,
  # vpc_id, target_type, name_prefix. AWS can't modify those in place. By
  # default Terraform deletes first, and AWS refuses with ResourceInUse while
  # the listener or the rule still forwards here. Reversed, it creates the new
  # group, repoints both, then deletes the old one. Needs name_prefix above, or
  # the create fails with "ELBv2 Target Group (...) already exists".
  lifecycle {
    create_before_destroy = true
  }
}

# The listener. HTTP on 80 without a certificate, HTTPS on 443 with one. TLS
# terminates here: the ALB decrypts and forwards to the tasks as plain HTTP
# inside the VPC (both target groups are HTTP), which is why the backend needs
# `trust proxy` to set a secure cookie. The default action is what a request
# gets when no rule matches: forward to the frontend. Forwarding is also what
# puts a target group in use, so the ALB starts probing its targets.
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = local.tls ? 443 : 80
  protocol          = local.tls ? "HTTPS" : "HTTP"

  # null leaves an argument out, as if it were never written: CFN's
  # AWS::NoValue. An HTTP listener rejects both. TLS 1.2 floor, 1.3 offered.
  ssl_policy      = local.tls ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main["frontend"].arn
  }
}

# The redirect listener, which exists only with TLS. Port 80 stops serving the
# app and 301s to HTTPS. The redirect is the default action with no rules above
# it, so it covers /api/* too. A 301 makes most clients re-issue a POST as a
# GET, so plain-HTTP API calls fail loudly rather than half-working.
resource "aws_lb_listener" "http_redirect" {
  count = local.tls ? 1 : 0

  # LOAD-BEARING on the HTTP -> HTTPS upgrade. Turning TLS on moves the app
  # listener 80 -> 443 and creates this one on 80. Nothing here references the
  # app listener, so Terraform starts both at once, and the create reaches AWS
  # while 80 is still taken: DuplicateListener (hit 2026-10-14). depends_on
  # holds the create until the move is done. A from-scratch create never hits
  # it, since the app listener is born on 443.
  depends_on = [aws_lb_listener.app]

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    # host, path and query are left to their defaults, #{host}, /#{path} and
    # #{query}: the same address, only the scheme and port change.
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# /api/* to the backend. Rules are evaluated lowest priority number first,
# whatever order they are written in; the default action has no priority and
# runs only when no rule matches.
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main["backend"].arn
  }
}
