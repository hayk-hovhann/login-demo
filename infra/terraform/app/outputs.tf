# Temporary: proves the network exports resolve. Replaced by the real outputs
# (URL, LoadBalancerDnsName, ...) as resources land.

output "vpc_id" {
  value = data.aws_cloudformation_export.vpc_id.value
}

output "subnet_ids" {
  value = [
    data.aws_cloudformation_export.subnet_a_id.value,
    data.aws_cloudformation_export.subnet_b_id.value,
  ]
}
