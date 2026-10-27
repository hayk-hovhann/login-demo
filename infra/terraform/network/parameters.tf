# Every value in local.published as an SSM parameter named after its output:
# /login-demo/network/vpc_id and so on. The same pattern as the data layer's
# parameters.tf, which explains the choices: a store rather than this config's
# state, Standard tier pinned, insecure_value because none of these is a
# secret.
#
# Unlike data's, these never come down: the network is permanent, so they
# stay put between sessions.
resource "aws_ssm_parameter" "published" {
  for_each = local.published

  name           = "${var.parameter_path}/${each.key}"
  type           = "String"
  tier           = "Standard"
  insecure_value = each.value
}
