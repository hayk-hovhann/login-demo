# The load balancer: LoadBalancer in app-ecs.yaml. AWS runs its nodes in both
# subnets, each one an ENI wearing the alb group, and one DNS name fronts them
# all. Use the name, never the IPs: they change as AWS replaces nodes. Bills
# from creation, ~$0.0225/hr, with or without traffic, and accepts nothing
# until a listener exists.
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

# Target groups: FrontendTargetGroup and BackendTargetGroup in app-ecs.yaml.
# Where the ALB sends a request once a rule has picked a service, and how it
# health-checks each destination. Created empty: each ECS service registers its
# tasks' IPs as they start. Free, and inert until a listener uses one; with no
# load balancer, nothing probes.
#
# A map rather than logs.tf's set, because the two differ: each.value carries
# the port and the health check path. aws_lb_target_group.service["backend"].
resource "aws_lb_target_group" "service" {
  for_each = {
    # 8080, the unprivileged nginx port. nginx serves index.html, so / is a 200.
    frontend = { port = 8080, health_check_path = "/" }

    # Liveness only, and never touches Postgres, so tasks go healthy before the
    # migration has run. Not /api/auth/me: anonymous, it returns 403, outside
    # the matcher, so no task could ever go healthy.
    backend = { port = 3000, health_check_path = "/api/health" }
  }

  name     = "${var.app_name}-${each.key}"
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
}
