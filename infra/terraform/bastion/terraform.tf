# The bastion: a private t3.micro reachable only through SSM Session Manager,
# for GUI tunnels to RDS (db-tunnel.sh) and, given the Redis badge, to Redis
# (redis-tunnel.sh). No inbound rules, no SSH key. Session-scoped: apply when
# GUI access is needed, destroy first at teardown. ~$7.50/mo if left running.
#
# Ported from infra/bastion.yaml, the CloudFormation template this config
# replaced, since removed: git show 65cd793:infra/bastion.yaml. Created fresh
# rather than imported, since nothing on it outlives a session. A comment here
# that compares with CloudFormation means that template.
#
# Reads the network and data layers' SSM parameters, so both must be applied
# first. Nothing locks data while the bastion runs: destroy this before it.
terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same bucket as the other configs, its own key. Literals only, as in every
  # backend block.
  backend "s3" {
    bucket       = "login-demo-tfstate-583534901308"
    key          = "bastion/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
