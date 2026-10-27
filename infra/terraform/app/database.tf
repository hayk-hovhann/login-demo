# The data layer publishes its values to SSM Parameter Store, one parameter
# per output of infra/terraform/data; this config reads them by name.
#
# A read takes no lock, and data comes down every session: nothing stops it
# going first. Destroy this config before data. With the parameters gone,
# every plan, apply and destroy here fails at the first read.
#
# insecure_value, not value: none of these is a secret, and value is marked
# sensitive, which would spread to everything built from it and hide both
# task definitions' environment in every plan.
data "aws_ssm_parameter" "db" {
  for_each = toset([
    "db_host",
    "db_port",
    "db_name",
    "db_secret_arn",
    "db_client_security_group_id",
  ])

  name = "${var.data_parameter_path}/${each.key}"
}

locals {
  # The five values by output name: local.db.db_host and so on.
  db = { for name, parameter in data.aws_ssm_parameter.db : name => parameter.insecure_value }

  # What the migrate and backend tasks both need to reach Postgres, written
  # once. The TLS settings are left out on purpose: the two tasks hand them to
  # different readers (Prisma's schema engine, pg in Node), so each task
  # definition carries its own, beside the comment that says why.
  db_environment = [
    { name = "DB_HOST", value = local.db.db_host },
    { name = "DB_PORT", value = local.db.db_port },
    { name = "DB_NAME", value = local.db.db_name },
  ]

  # The RDS-managed master secret is JSON with username and password keys.
  # <arn>:<json-key>:<version-stage>:<version-id>, the last two empty: one key
  # of the secret's JSON per env var. Read from the secret rather than
  # hardcoding 'appuser', so it stays right across snapshot restores.
  db_secrets = [
    { name = "DB_USER", valueFrom = "${local.db.db_secret_arn}:username::" },
    { name = "DB_PASSWORD", valueFrom = "${local.db.db_secret_arn}:password::" },
  ]
}
