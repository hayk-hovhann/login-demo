# The ECS cluster: Cluster in app-ecs.yaml. The namespace the backend and
# frontend services run in. On Fargate it holds no machines, so it costs nothing
# on its own; the tasks placed in it are what bill.
#
# The name keeps CloudFormation's capital C, unlike every other name here,
# because three things find the cluster by name rather than by reference: CD's
# locate step (cd.yml:115, :233) by the case-sensitive substring
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
