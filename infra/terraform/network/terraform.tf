# The network: one VPC, two public subnets, an internet gateway and the route
# between them. Permanent: every other layer is built inside it, and it costs
# nothing at rest.
#
# Adopted from infra/network.yaml, the CloudFormation template this config
# replaced, since removed: git show c858e0c:infra/network.yaml. Imported in
# place rather than recreated, because destroying the VPC would take every
# layer inside it down too; the import blocks are in the same commit, at
# infra/terraform/network/imports.tf. A comment here that compares with
# CloudFormation means that template.
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
