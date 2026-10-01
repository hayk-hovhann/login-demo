# The network stays in CloudFormation. Its exports are the seam: where
# app-ecs.yaml says Fn::ImportValue, this config reads a data source.
#
# Unlike ImportValue, a data source does NOT lock the export. CloudFormation
# will let the network stack be deleted while this config still depends on it.

data "aws_cloudformation_export" "vpc_id" {
  name = "${var.network_stack_name}-VpcId"
}

data "aws_cloudformation_export" "subnet_a_id" {
  name = "${var.network_stack_name}-SubnetAId"
}

data "aws_cloudformation_export" "subnet_b_id" {
  name = "${var.network_stack_name}-SubnetBId"
}
