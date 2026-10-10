# The task execution role: TaskExecutionRole in app-ecs.yaml. What Fargate
# itself uses to START a task, before any app code runs: pull the image from
# ECR, ship logs to CloudWatch, and fetch secrets to inject as env vars.
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
# The session secret only, for now. The RDS secret (the data stack's
# DbSecretArn export) joins this list with the backend task definition, the
# first resource here that needs the data stack anyway.
resource "aws_iam_role_policy" "task_execution_read_secrets" {
  name = "read-secrets"
  role = aws_iam_role.task_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [aws_secretsmanager_secret.session.arn]
    }]
  })
}
