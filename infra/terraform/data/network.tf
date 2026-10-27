# The network layer's values, read from SSM Parameter Store the same way as
# the app's network.tf. The network is permanent, so they are always there.
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
