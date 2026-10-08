# The express-session signing key: SessionSecret in app-ecs.yaml. ECS reads it
# at task start and hands it to the backend as SESSION_SECRET.
#
# This block is only the container. Its value is set by a separate resource.
resource "aws_secretsmanager_secret" "session" {
  name        = "${var.app_name}-session-secret"
  description = "express-session signing key for ${var.app_name}"

  # Destroy deletes it outright. The default is a 30-day recovery window, during
  # which the name stays taken and the next apply's create fails (CloudFormation
  # dodged that by leaving Name unpinned). The delete itself is asynchronous, so
  # an apply straight after a destroy can still briefly hit the old name; re-run.
  recovery_window_in_days = 0
}

# Generates the value: GenerateSecretString in app-ecs.yaml, here as a direct
# call to AWS's own password generator. Ephemeral: the result exists only for
# the run and is never written to plan or state.
ephemeral "aws_secretsmanager_random_password" "session" {
  password_length     = 64
  exclude_punctuation = true # keeps it shell/env-var safe
}

# Puts the value in the secret. secret_string_wo is write-only: sent to AWS,
# never recorded. With no copy to compare against, Terraform cannot tell when
# the value changes, so it sends one only on create or when
# secret_string_wo_version changes. A fresh password is generated on every run;
# this is what keeps it from reaching AWS, where it would log every user out.
resource "aws_secretsmanager_secret_version" "session" {
  secret_id                = aws_secretsmanager_secret.session.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.session.random_password
  secret_string_wo_version = 1
}
