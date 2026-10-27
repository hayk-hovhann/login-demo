# The network layer publishes its values to SSM Parameter Store, one parameter
# per output of infra/terraform/network; this config reads them by name, as
# database.tf reads data's. The network is permanent, so unlike data's these
# are always there.
#
# insecure_value, not value: none of these is a secret, and value is marked
# sensitive, which would spread to every subnet list and vpc_id built from it.
data "aws_ssm_parameter" "network" {
  for_each = toset([
    "vpc_id",
    "subnet_a_id",
    "subnet_b_id",
  ])

  name = "${var.network_parameter_path}/${each.key}"
}

locals {
  # The three values by output name: local.network.vpc_id and so on.
  network = { for name, parameter in data.aws_ssm_parameter.network : name => parameter.insecure_value }
}
