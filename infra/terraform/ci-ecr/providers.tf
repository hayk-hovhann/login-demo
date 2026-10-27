provider "aws" {
  region = "us-east-1"

  # Stamped on every resource this config manages, adopted ones included: the
  # first apply adds both tags to resources CloudFormation created without them.
  default_tags {
    tags = {
      Project   = "login-demo"
      ManagedBy = "terraform"
    }
  }
}
