# What every other layer needs from the network: the VPC to build in and the
# two subnets to place things in. Written once here; each value goes out twice,
# as an output below for terraform output at the terminal, and as an SSM
# parameter (parameters.tf) for every other reader.
locals {
  published = {
    vpc_id      = aws_vpc.main.id
    subnet_a_id = aws_subnet.a.id
    subnet_b_id = aws_subnet.b.id

    # No reader yet. Kept because CloudFormation exported it, for a security
    # group rule that needs the VPC's range as a CIDR.
    vpc_cidr = aws_vpc.main.cidr_block
  }
}

output "vpc_id" {
  description = "The VPC every other layer is built in."
  value       = local.published.vpc_id
}

output "subnet_a_id" {
  description = "Public subnet in the first availability zone."
  value       = local.published.subnet_a_id
}

output "subnet_b_id" {
  description = "Public subnet in the second availability zone."
  value       = local.published.subnet_b_id
}

output "vpc_cidr" {
  description = "The VPC's IPv4 range."
  value       = local.published.vpc_cidr
}
