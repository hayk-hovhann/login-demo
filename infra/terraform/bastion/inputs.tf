# What the bastion is built from, read from the parameters the network and
# data layers publish, the same way the app reads them. insecure_value, not
# value: none of these is a secret.
data "aws_ssm_parameter" "network" {
  for_each = toset([
    "vpc_id",
    "subnet_a_id",
  ])

  name = "${var.network_parameter_path}/${each.key}"
}

# The badge that lets the bastion through to Postgres on 5432.
data "aws_ssm_parameter" "db_client_security_group_id" {
  name = "${var.data_parameter_path}/db_client_security_group_id"
}

# The current Amazon Linux 2023 AMI, from AWS's public parameter: never
# hardcoded.
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # The two values by output name: local.network.vpc_id and so on.
  network = { for name, parameter in data.aws_ssm_parameter.network : name => parameter.insecure_value }
}
