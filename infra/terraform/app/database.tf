# The data stack stays in CloudFormation until its own arc. Same seam as
# network.tf: its Db* exports are read through data sources, not imported.
#
# The missing lock matters more here than for the network, which is permanent:
# data comes down every session, and CloudFormation won't stop it going first.
# Destroy this config before deleting data. With the exports gone, every plan,
# apply and destroy here fails at the first read.

data "aws_cloudformation_export" "db_endpoint" {
  name = "${var.data_stack_name}-DbEndpoint"
}

data "aws_cloudformation_export" "db_port" {
  name = "${var.data_stack_name}-DbPort"
}

data "aws_cloudformation_export" "db_name" {
  name = "${var.data_stack_name}-DbName"
}

# The RDS-managed master secret: JSON with username and password keys. The
# backend and migrate tasks pull each key into its own env var at task start.
data "aws_cloudformation_export" "db_secret_arn" {
  name = "${var.data_stack_name}-DbSecretArn"
}

# The empty client group the DB's own group admits on 5432. A task wearing it
# can reach Postgres; that is the whole grant.
data "aws_cloudformation_export" "db_client_sg_id" {
  name = "${var.data_stack_name}-DbClientSgId"
}

# What the migrate and backend tasks both need to reach Postgres, written once.
# The TLS settings are left out on purpose: the two tasks hand them to different
# readers (Prisma's schema engine, pg in Node), so each task definition carries
# its own, beside the comment that says why.
locals {
  db_environment = [
    { name = "DB_HOST", value = data.aws_cloudformation_export.db_endpoint.value },
    { name = "DB_PORT", value = data.aws_cloudformation_export.db_port.value },
    { name = "DB_NAME", value = data.aws_cloudformation_export.db_name.value },
  ]

  # <arn>:<json-key>:<version-stage>:<version-id>, the last two empty: one key
  # of the secret's JSON per env var. Read from the secret rather than
  # hardcoding 'appuser', so it stays right across snapshot restores.
  db_secrets = [
    { name = "DB_USER", valueFrom = "${data.aws_cloudformation_export.db_secret_arn.value}:username::" },
    { name = "DB_PASSWORD", valueFrom = "${data.aws_cloudformation_export.db_secret_arn.value}:password::" },
  ]
}
