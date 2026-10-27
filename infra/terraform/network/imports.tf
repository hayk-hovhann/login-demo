# One-time adoption of what infra/network.yaml created. Each block makes the
# next plan read an existing resource into state instead of creating it; once
# applied, it is a no-op. Removed with network.yaml, once the CloudFormation
# stack is gone.
#
# Eight blocks for CloudFormation's nine resources: its VPCGatewayAttachment is
# the internet gateway's vpc_id here. Composite ids use the provider's formats:
# a route is <table>_<destination>, an association <subnet>/<table>.

import {
  to = aws_vpc.main
  id = "vpc-073b969f9d7a88b6d"
}

import {
  to = aws_internet_gateway.main
  id = "igw-041c9e73e4765c0fc"
}

import {
  to = aws_subnet.a
  id = "subnet-096fdd21e18a0fe80"
}

import {
  to = aws_subnet.b
  id = "subnet-0582139a9c7865d9a"
}

import {
  to = aws_route_table.public
  id = "rtb-05f95b55c5e3c4f7c"
}

import {
  to = aws_route.internet
  id = "rtb-05f95b55c5e3c4f7c_0.0.0.0/0"
}

import {
  to = aws_route_table_association.a
  id = "subnet-096fdd21e18a0fe80/rtb-05f95b55c5e3c4f7c"
}

import {
  to = aws_route_table_association.b
  id = "subnet-0582139a9c7865d9a/rtb-05f95b55c5e3c4f7c"
}
