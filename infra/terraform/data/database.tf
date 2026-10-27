# Postgres on RDS. Its two security groups live in security_groups.tf.

# Which subnets RDS may place the instance in. RDS refuses a group that covers
# fewer than two availability zones, even for a single-AZ instance, so there is
# always somewhere to put a Multi-AZ standby. Free on its own; the instance
# that uses it is what bills.
#
# These are the network's public subnets, the only kind it has (no NAT). The
# instance stays off the internet anyway: it gets no public IP, and its group
# admits only the badge.
resource "aws_db_subnet_group" "db" {
  name        = "${var.data_name}-db"
  description = "${var.data_name} db subnets"
  subnet_ids = [
    local.network.subnet_a_id,
    local.network.subnet_b_id,
  ]
}

# The database: Postgres 16, single-AZ, private. ~$12-15/mo if left up, and
# RDS has no real off switch, so it comes down every session. The final
# snapshot at the bottom is what makes that safe.
resource "aws_db_instance" "db" {
  identifier     = "${var.data_name}-db"
  engine         = "postgres"
  engine_version = "16.11"
  instance_class = var.instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  # The provider's default is false.
  storage_encrypted = true

  db_name  = "logindemo"
  username = "appuser"

  # Null creates a blank database; a snapshot id restores from it. On restore
  # the provider never sends db_name or username (the snapshot carries its
  # own, the same two) and reads them back afterwards, and storage_encrypted
  # above already matches the snapshot's: nothing here has to switch off.
  #
  # Computed as well as force-new: clearing the variable after a restore keeps
  # what state recorded, a no-op, but naming a different snapshot plans a
  # replacement, final snapshot first.
  snapshot_identifier = var.snapshot_identifier

  # RDS generates the master password, keeps it in Secrets Manager and rotates
  # it; it never passes through this config or its state. Consumers read the
  # secret's ARN from master_user_secret[0].secret_arn.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  # Which RDS CA signs the server cert. It must be a root in
  # backend/certs/rds-us-east-1-bundle.pem, and specifically the FIRST one:
  # whether Prisma's schema engine reads past the first cert in a bundle is
  # unverified, and RSA2048 is first in the file.
  ca_cert_identifier = "rds-ca-rsa2048-g1"

  # Lets humans log in with a short-lived SigV4 token instead of the master
  # password: GRANT rds_iam to a DB role, then pass the output of
  # `aws rds generate-db-auth-token` as the password. The role lives in the
  # data, so it survives a snapshot restore. The DbiResourceId in an
  # rds-db:connect policy ARN does not: it changes on every restore, so
  # wildcard it.
  iam_database_authentication_enabled = true

  backup_retention_period = 1

  # The provider's default is false, which leaves every snapshot untagged,
  # the final one included: the one resource that outlives the teardown. True
  # copies the instance's tags, default_tags included, onto each.
  copy_tags_to_snapshot = true

  # An edit lands now, not in the next maintenance window. The provider's
  # default is false, and then every plan until the window shows the edit
  # again.
  apply_immediately = true

  # A final snapshot on destroy: CloudFormation's DeletionPolicy: Snapshot. A
  # replacement is a destroy plus a create, so it also covers
  # UpdateReplacePolicy: Snapshot.
  #
  # CloudFormation named the snapshot itself; here a name is mandatory, and
  # the provider asks for it only at destroy, so a missing one fails the
  # teardown, not the apply. It must also be unique: a fixed name fails the
  # next teardown while the last snapshot still exists, which is exactly when
  # you are keeping it to restore from. timestamp() is read once, at create;
  # ignore_changes stops every later plan from moving it.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.data_name}-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}
