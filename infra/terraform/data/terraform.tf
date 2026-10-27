# The data layer: Postgres on RDS, being ported from infra/data.yaml. Its own
# config and its own state, apart from infra/terraform/app, because the two
# live on different clocks: the app can be destroyed and rebuilt at will, the
# database holds the only copy of the users. Whatever shares a state file
# shares every plan, apply and destroy, so a separate key is what keeps a
# destroy in app from ever reaching the database.
terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same bucket as the app, its own key: data/terraform.tfstate beside
  # app/terraform.tfstate. The lock file sits beside the key too, so an apply
  # here never waits on one in app. Literals only, as in every backend block.
  backend "s3" {
    bucket       = "login-demo-tfstate-583534901308"
    key          = "data/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
