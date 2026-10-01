provider "aws" {
  region = "us-east-1"

  # Stamped on every resource this config creates.
  default_tags {
    tags = {
      Project   = "login-demo"
      ManagedBy = "terraform"
    }
  }
}
