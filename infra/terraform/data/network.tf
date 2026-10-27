# The network stays in CloudFormation until its own arc. Same seam as the
# app's network.tf: its exports, read through data sources rather than
# imported, and so not locked. The network is permanent, so the missing lock
# costs little here.

data "aws_cloudformation_export" "vpc_id" {
  name = "${var.network_stack_name}-VpcId"
}

data "aws_cloudformation_export" "subnet_a_id" {
  name = "${var.network_stack_name}-SubnetAId"
}

data "aws_cloudformation_export" "subnet_b_id" {
  name = "${var.network_stack_name}-SubnetBId"
}
