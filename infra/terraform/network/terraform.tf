# The network: one VPC, two public subnets, an internet gateway and the route
# between them. Permanent: every other layer is built inside it, and it costs
# nothing at rest. Adopted from infra/network.yaml with import blocks
# (imports.tf) rather than recreated, because destroying the VPC would take
# every layer inside it down too.
terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same bucket as app and data, its own key. Literals only, as in every
  # backend block.
  backend "s3" {
    bucket       = "login-demo-tfstate-583534901308"
    key          = "network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
