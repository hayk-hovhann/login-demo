# The instance's own group, with no ingress at all. SSM needs none: the agent
# dials out to AWS, so nothing can connect to this box.
resource "aws_security_group" "bastion" {
  name        = var.bastion_name
  description = "${var.bastion_name} (no ingress; SSM outbound only)"
  vpc_id      = local.network.vpc_id
}

# The only egress among the instance's groups: the badges carry none. AWS
# gives every new group allow-all, and CloudFormation kept it; Terraform
# strips it on create. Without this the SSM agent never registers, and the
# tunnels could not reach Postgres or Redis anyway.
resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Lets the SSM agent register and run sessions. The AWS-managed
# AmazonSSMManagedInstanceCore policy is exactly that scope, nothing more.
resource "aws_iam_role" "bastion" {
  name = var.bastion_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = var.bastion_name
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ssm_parameter.ami.insecure_value
  instance_type = "t3.micro"

  # A public IP only so the SSM agent has a way out: this VPC has no NAT. With
  # no inbound rules it is still unreachable from anywhere.
  subnet_id                   = local.network.subnet_a_id
  associate_public_ip_address = true

  # Its own group for egress, the DB badge for 5432, and the Redis badge for
  # 6379 only when one was passed.
  vpc_security_group_ids = concat(
    [
      aws_security_group.bastion.id,
      data.aws_ssm_parameter.db_client_security_group_id.insecure_value,
    ],
    var.redis_client_security_group_id == null ? [] : [var.redis_client_security_group_id],
  )

  iam_instance_profile = aws_iam_instance_profile.bastion.name

  # IMDSv2 only, as the AL2023 AMI already defaults to; stated so the setting
  # does not depend on which AMI the parameter resolves to.
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = var.bastion_name
  }

  # The AMI parameter is read on every plan; without this, an AMI release
  # mid-session would plan replacing a running bastion. The AMI is fixed at
  # create, as CloudFormation fixed it.
  lifecycle {
    ignore_changes = [ami]
  }
}
