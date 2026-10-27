# The VPC and what makes its subnets public. Nothing here bills. There is no
# NAT gateway on purpose (~$32/mo): tasks get public IPs and go out through
# the internet gateway instead.
#
# prevent_destroy on the VPC and both subnets: their ids are what every other
# layer is built on, so a plan that would replace one fails instead of
# offering to. Remove the line deliberately, never to get a plan through.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = "172.31.0.0/16"

  # RDS endpoints and other AWS service names resolve only with both on. The
  # provider's default for hostnames is false.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.network_name}-vpc"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# vpc_id is the attachment: one resource where CloudFormation had two.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.network_name}-igw"
  }
}

# Two subnets in two zones: the ALB and the RDS subnet group each refuse
# fewer. The first two available zones, as CloudFormation's !GetAZs picked
# them. The CIDRs are as created, a on .38 and b on .37; either one changed
# plans a replacement.
resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = "172.31.38.0/24"

  tags = {
    Name = "${var.network_name}-subnet-a"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[1]
  cidr_block        = "172.31.37.0/24"

  tags = {
    Name = "${var.network_name}-subnet-b"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# One route table for both subnets. Its routes are separate aws_route
# resources: never add an inline route block here as well, or the two
# overwrite each other.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.network_name}-rt"
  }
}

# The route that makes the subnets public.
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.public.id
}
