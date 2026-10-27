# The badge: no rules at all. Wearing it is what db_from_client admits on 5432;
# the backend tasks, the migrate task and the bastion all wear it. Owned here,
# not by the app, because the app is created after the database and destroyed
# before it: the database's group can only admit a group that already exists
# and outlives it.
#
# No egress either: a network interface gets the union of all its groups'
# rules, so the wearer's main group supplies outbound. CloudFormation kept
# AWS's allow-all here; dropped on purpose, as on the app's Redis badge.
resource "aws_security_group" "db_client" {
  name        = "${var.data_name}-db-client"
  description = "${var.data_name}-db-client (attach to anything that needs Postgres)"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

# The database's own group. Postgres still wants a password, but nothing
# without the badge gets as far as asking.
resource "aws_security_group" "db" {
  name        = "${var.data_name}-db"
  description = "${var.data_name}-db"
  vpc_id      = data.aws_cloudformation_export.vpc_id.value
}

# A separate rule resource, not an inline ingress block, as in the app.
resource "aws_vpc_security_group_ingress_rule" "db_from_client" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.db_client.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# No egress rule: Postgres never opens a connection here, it only replies, and
# statefulness lets replies out. CloudFormation kept AWS's allow-all here;
# dropped on purpose, as on the app's Redis group.
