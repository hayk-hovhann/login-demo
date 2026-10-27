# Every value in local.published as an SSM parameter named after its output:
# /login-demo/data/db_host and so on. This is how readers outside this config
# find them. Terraform cannot create CloudFormation exports, and HashiCorp's
# advice is to publish to a separate store rather than have readers open this
# config's state; a store also serves readers that aren't Terraform. The app
# reads these with data "aws_ssm_parameter", the bastion through an
# AWS::SSM::Parameter::Value<...> parameter, the scripts with
# aws ssm get-parameter.
#
# Standard tier, pinned: free, and 4 KB is plenty for an id. Left unset it is
# the account's default tier, which a setting elsewhere could make Advanced,
# and billed. insecure_value, not value: none of these is a secret (the
# password stays in Secrets Manager), and value would show every one of them
# in plan output as (sensitive value).
#
# Destroyed with the database, so a reader that runs too early or too late
# fails on a missing parameter instead of using a stale one.
resource "aws_ssm_parameter" "published" {
  for_each = local.published

  name           = "${var.parameter_path}/${each.key}"
  type           = "String"
  tier           = "Standard"
  insecure_value = each.value
}
