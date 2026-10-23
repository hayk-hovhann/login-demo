# The ECS cluster: Cluster in app-ecs.yaml. The namespace the backend and
# frontend services run in. On Fargate it holds no machines, so it costs nothing
# on its own; the tasks placed in it are what bill.
#
# The name keeps CloudFormation's capital C, unlike every other name here,
# because three things find the cluster by name rather than by reference: CD's
# locate step (cd.yml:115, :242) by the case-sensitive substring
# 'login-demo-app-Cluster', skipping the deploy silently if nothing matches;
# run-migration.sh:46, which builds the exact name; and the dashboard's
# ClusterName dimension, once it is ported.
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-Cluster"
}

# ci-ecr-oidc.yaml outputs the repo URIs but does not export them, so the repo
# is looked up by name. If it is gone, plan fails here rather than a task
# failing to pull later.
data "aws_ecr_repository" "frontend" {
  name = "login-demo-frontend"
}

data "aws_region" "current" {}

# The frontend task definition: FrontendTaskDefinition in app-ecs.yaml. The
# recipe ECS starts a task from: image, size, port, roles, log destination.
# Free; nothing runs until a service or run-task uses it.
#
# Immutable. Each registration is a numbered revision of a family
# (login-demo-app-frontend:19), so any change here plans as a replacement, never
# an in-place update: a new revision is registered, the old one deregistered.
# Deregistered means INACTIVE, not deleted, and destroy leaves the last one
# behind the same way.
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.app_name}-frontend"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # Starts it: pulls the image, creates the log stream. No task_role_arn:
  # nginx makes no AWS calls, and ECS Exec is backend-only.
  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${data.aws_ecr_repository.frontend.repository_url}:${var.frontend_image_tag}"
    essential = true

    # nginx-unprivileged cannot bind below 1024. The ALB still listens on 80/443.
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["frontend"].name
        "awslogs-stream-prefix" = "frontend"
      }
    }
  }])
}

# The frontend service: FrontendService in app-ecs.yaml. Keeps desired_count
# tasks running from one task definition revision, registers each task's IP in
# the frontend target group, and replaces a task that stops or fails its health
# checks. Free on its own; its tasks are what bill.
#
# The name keeps CloudFormation's form for the same reason as the cluster's:
# CD's locate step (cd.yml:224) finds the service by the substring
# 'login-demo-app-FrontendService' and skips the deploy silently if nothing
# matches.
resource "aws_ecs_service" "frontend" {
  # LOAD-BEARING. ECS rejects a target group that no listener forwards to yet,
  # and nothing here references the listener, so without this Terraform would
  # create both at once.
  depends_on = [aws_lb_listener.app]

  name            = "${var.app_name}-FrontendService"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1

  # Left out, the service falls back to EC2, and this cluster has no instances.
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  # For a new task's first 60 s, ECS ignores the target group's health checks,
  # so a slow start is not counted as a failure.
  health_check_grace_period_seconds = 60

  # Rolling deploy: start the new task, wait for it to go healthy, then stop the
  # old one. With one desired task: never fewer than one running, at most two.
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # A deploy whose tasks keep failing is stopped and rolled back to the last
  # deployment that completed.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main["frontend"].arn
    container_name   = "frontend"
    container_port   = 8080
  }

  # Public subnets plus a public IP: the task reaches ECR and CloudWatch Logs
  # through the internet gateway, with no NAT gateway to pay for.
  network_configuration {
    subnets = [
      data.aws_cloudformation_export.subnet_a_id.value,
      data.aws_cloudformation_export.subnet_b_id.value,
    ]
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  # Two writers on one field. CD points the service at a new revision on every
  # deploy (cd.yml:302); without this, the next apply would point it back at
  # Terraform's. The price: once the service exists, an edit to the task
  # definition above does not reach the tasks at apply. It waits for CD's next
  # deploy, which copies the family's latest revision (cd.yml:282), so it picks
  # the edit up. The field is read only when the service is created.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
