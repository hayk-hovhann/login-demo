terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in the bucket from infra/tf-state.yaml, not on this laptop.
  # One bucket, one key per stack, so each stack gets its own state file.
  # Backend blocks cannot use variables: every value here must be a literal,
  # which is why tf-state.yaml pins the bucket name.
  backend "s3" {
    bucket       = "login-demo-tfstate-583534901308"
    key          = "app/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
