# CI's footprint in AWS: the two ECR repositories CD pushes images to, and the
# identity it pushes and deploys as, GitHub's OIDC provider and the role a
# workflow on main may assume. Permanent; nothing here bills beyond ECR
# storage, which the lifecycle policies cap.
#
# Adopted from infra/ci-ecr-oidc.yaml, the CloudFormation template this config
# replaced, since removed: git show 374c35a:infra/ci-ecr-oidc.yaml. Imported
# in place rather than recreated: a new repository starts empty, and a
# recreated provider or role fails every CD run in between. The import blocks
# were applied once and not kept; the resources are in state. A comment here
# that compares with CloudFormation means that template.
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
    key          = "ci-ecr/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
