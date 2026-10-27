# The task execution role. What Fargate itself uses to START a task, before
# any app code runs: pull the image from ECR, ship logs to CloudWatch, and
# fetch secrets to inject as env vars.
#
# Split into three resources, like the security-group rules: the role, the
# AWS-managed policy attached to it, and an inline policy. aws_iam_role's own
# managed_policy_arns argument is deprecated in provider 6.x.
resource "aws_iam_role" "task_execution" {
  name = "${var.app_name}-task-execution"

  # Who may assume it: ECS tasks, and nothing else.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ECR pull + CloudWatch Logs. AWS-managed, so AWS keeps it current.
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy does not cover Secrets Manager. Without this, a task that
# references a secret fails to start with ResourceInitializationError.
#
# Two secrets: the session key, this config's own, and the RDS-managed master
# secret, from the data layer's db_secret_arn parameter. The bare secret ARN:
# the :username:: suffix is ECS's valueFrom syntax, not part of the IAM
# resource.
resource "aws_iam_role_policy" "task_execution_read_secrets" {
  name = "read-secrets"
  role = aws_iam_role.task_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_secretsmanager_secret.session.arn,
        local.db.db_secret_arn,
      ]
    }]
  })
}

# The task role. What code inside a RUNNING task uses for its own AWS calls.
# The app makes none; the only user is ECS Exec, whose agent in the container
# opens its SSM channel with it. Only the backend's task definition names this
# role.
#
# Same trust policy as the execution role. Which role does which job is decided
# by the task definition: execution_role_arn to start, task_role_arn to run.
resource "aws_iam_role" "task" {
  name = "${var.app_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ECS Exec's channel. Resource is "*" because ssmmessages cannot be scoped:
# AWS's authorization reference lists no resource types for it. Granted whether
# exec is on or off; the switch is the backend service's enable_execute_command
# (var.enable_exec, default off).
resource "aws_iam_role_policy" "task_ecs_exec" {
  name = "ecs-exec-ssm"
  role = aws_iam_role.task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}
