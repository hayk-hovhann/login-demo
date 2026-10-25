# The ECS cluster. The namespace the backend and frontend services run in. On
# Fargate it holds no machines, so it costs nothing on its own; the tasks placed
# in it are what bill.
#
# The name keeps CloudFormation's capital C, unlike every other name here,
# because CD's locate step (cd.yml:115, :242) finds the cluster by the
# case-sensitive substring 'login-demo-app-Cluster', and skips the deploy
# silently if nothing matches. run-migration.sh and the dashboard read the name
# from here instead.
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-Cluster"
}

# ci-ecr-oidc.yaml outputs the repo URIs but does not export them, so each repo
# is looked up by name. If one is gone, plan fails here rather than a task
# failing to pull later.
data "aws_ecr_repository" "frontend" {
  name = "login-demo-frontend"
}

# One repo, two images: the backend under <tag>, the Dockerfile's migrate stage
# under migrate-<tag> (cd.yml:82).
data "aws_ecr_repository" "backend" {
  name = "login-demo-backend"
}

data "aws_region" "current" {}

# The frontend task definition. The recipe ECS starts a task from: image, size,
# port, roles, log destination. Free; nothing runs until a service or run-task
# uses it.
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

# The frontend service. Keeps desired_count tasks running from one task
# definition revision, registers each task's IP in the frontend target group,
# and replaces a task that stops or fails its health checks. Free on its own;
# its tasks are what bill.
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

  # What "Apply complete!" means. Left at the default false, apply returns as
  # soon as ECS has accepted the service, so a broken image still ends in
  # success while the circuit breaker gives up out of sight. True waits for the
  # deployment to complete, its tasks running and healthy in the target group,
  # and fails the apply with ECS's reason if it doesn't. Costs the time for the
  # first task to go healthy, on create; Terraform rarely updates the service,
  # since CD owns the revision. Gives up after the 20m default timeout.
  wait_for_steady_state = true

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

# The migrate task definition. Not a service: nothing runs until
# run-migration.sh calls run-task with it, and the task stops when
# `prisma migrate deploy` exits. Deliberately not an init container on the
# backend: a failed migration there trips the circuit breaker, whose rollback
# deletes the logs you need to diagnose it.
#
# run-migration.sh starts it by the family the migrate_task_definition_family
# output names, and supplies the network config itself (:61), the db client
# group included.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.app_name}-migrate"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # Pulls the image, creates the log stream, reads the RDS secret. No
  # task_role_arn: Prisma makes no AWS calls.
  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name = "migrate"

    # The runtime image has no prisma CLI, so migrations run from the
    # Dockerfile's migrate stage, built from the same commit as the backend:
    # one tag variable drives both images.
    image     = "${data.aws_ecr_repository.backend.repository_url}:migrate-${var.backend_image_tag}"
    essential = true

    # Read by prisma.config.ts, not by any driver: the schema engine takes TLS
    # settings only as URL parameters, so sslParams() turns these into them.
    # Not the backend's NODE_EXTRA_CA_CERTS: the engine is not Node and never
    # consults Node's root store. Same bundle file, different reader.
    environment = concat(local.db_environment, [
      { name = "PGSSLMODE", value = "verify-full" },
      { name = "PGSSLROOTCERT", value = "/app/certs/rds-us-east-1-bundle.pem" },
    ])
    secrets = local.db_secrets

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["migrate"].name
        "awslogs-stream-prefix" = "migrate"
      }
    }
  }])
}

# The backend task definition. The frontend's shape plus what the API needs to
# reach Postgres and Redis and to sign sessions. Same two-writer story as the
# frontend: CD copies the family's latest revision on every backend deploy
# (cd.yml:155).
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.app_name}-backend"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # Starts it: pulls the image, creates the log stream, reads both secrets.
  execution_role_arn = aws_iam_role.task_execution.arn

  # Runs it: the identity the container's own AWS calls use. The app makes
  # none; this is for ECS Exec's SSM channel, off unless the service turns
  # enable_execute_command on.
  task_role_arn = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${data.aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
    essential = true

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    # Plaintext: visible in the console and in describe-task-definition.
    environment = concat(local.db_environment, [
      { name = "PORT", value = "3000" },

      # From the listener shape, not set by hand, so it can't drift from the
      # transport. A secure cookie over plain HTTP is never sent back by the
      # browser, which looks exactly like a broken login.
      { name = "COOKIE_SECURE", value = tostring(local.tls) },

      { name = "REDIS_URL", value = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}" },

      # TLS to RDS, read by pg in Node. RDS forces SSL, but pg opens a plaintext
      # socket unless told otherwise, and the refusal surfaces through Prisma as
      # P1010 "User was denied access": it reads like bad credentials. pg reads
      # PGSSLMODE whenever its config omits ssl. verify-full checks the chain and
      # that the cert names DB_HOST; not `require`, which pg 9 turns into
      # encrypt-without-verify. Node's roots lack the RDS CA, so
      # NODE_EXTRA_CA_CERTS adds the bundle. A bad path only warns at startup
      # ("Ignoring extra certs"): the task still goes healthy, then every query
      # fails.
      { name = "PGSSLMODE", value = "verify-full" },
      { name = "NODE_EXTRA_CA_CERTS", value = "/app/certs/rds-us-east-1-bundle.pem" },

      { name = "REGISTRATION_ENABLED", value = tostring(var.registration_enabled) },
    ])

    # Resolved by the execution role at task start, injected as env vars. The
    # values never appear in the task definition, the console, or state.
    secrets = concat(local.db_secrets, [
      # The version's secret_arn, not the secret's arn: the same ARN, but
      # pointing at the version is what makes Terraform put the value in before
      # anything that could start a task reading it.
      { name = "SESSION_SECRET", valueFrom = aws_secretsmanager_secret_version.session.secret_arn },
    ])

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-group"         = aws_cloudwatch_log_group.ecs["backend"].name
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])
}

# The backend service. The frontend service's settings, with three
# differences: a second security group, ECS Exec, and the /api/* rule in
# depends_on instead of the listener.
#
# The name keeps CloudFormation's form: CD's locate step (cd.yml:97) finds the
# service by the substring 'login-demo-app-BackendService' and skips the deploy
# silently if nothing matches.
resource "aws_ecs_service" "backend" {
  # LOAD-BEARING, the frontend's reason one level down. Only the /api/* rule
  # forwards to the backend target group, so ECS rejects the group until the
  # rule exists, and nothing here references the rule.
  depends_on = [aws_lb_listener_rule.api]

  name            = "${var.app_name}-BackendService"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn

  # Sessions live in Redis and every task shares one signing secret, so more
  # than one task would work; one is enough for a session-scoped stack.
  desired_count = 1

  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  # Break-glass shell into a running task, off by default. The task role
  # already carries the SSM channel permissions; this is the switch.
  enable_execute_command = var.enable_exec

  # Liveness only (/api/health never touches Postgres), so a task goes healthy
  # before the migration has run, and the 60 s covers the slow start.
  health_check_grace_period_seconds = 60

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # As on the frontend: apply completes only once a task is running and
  # healthy, and fails with ECS's reason if none ever is.
  wait_for_steady_state = true

  load_balancer {
    target_group_arn = aws_lb_target_group.main["backend"].arn
    container_name   = "backend"
    container_port   = 3000
  }

  network_configuration {
    subnets = [
      data.aws_cloudformation_export.subnet_a_id.value,
      data.aws_cloudformation_export.subnet_b_id.value,
    ]

    # Two groups, unioned on the task's network card. service admits the ALB
    # on 3000 and is what Redis admits on 6379. The db client group is the
    # data stack's empty badge, the one the DB's own group admits on 5432.
    security_groups = [
      aws_security_group.service.id,
      data.aws_cloudformation_export.db_client_sg_id.value,
    ]
    assign_public_ip = true
  }

  # Two writers on one field, as on the frontend: CD owns the revision after
  # create (cd.yml:170).
  lifecycle {
    ignore_changes = [task_definition]
  }
}
