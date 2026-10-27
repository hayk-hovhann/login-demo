# GitHub's token issuer, registered as something this account trusts. One per
# issuer per account: any other repository's workflows would share it.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's thumbprint, required when the provider was created. AWS now
  # verifies GitHub's certificate chain itself, so the value is a formality.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# The role CD assumes, by the ARN in the repository's AWS_ROLE_ARN variable:
# renaming it breaks CD until that variable follows.
#
# Trust: a workflow run on main in this repository, proven by GitHub's OIDC
# token. A branch or pull request run is refused by AWS itself, matching the
# pipeline rule that images ship only on merge to main.
resource "aws_iam_role" "github_actions" {
  name = "login-demo-github-actions-ecr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Push. GetAuthorizationToken is account-level, so it takes Resource "*"; the
# layer and image actions are scoped to the two repositories, every tag.
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [for repository in aws_ecr_repository.service : repository.arn]
      },
    ]
  })
}

# Deploy: CD's locate step finds the cluster and service, reads the live task
# definition, registers a revision pinned to the new image and rolls the
# service to it. RegisterTaskDefinition embeds the execution role, so the
# deploy identity must be allowed to pass a role, but only to ECS tasks.
resource "aws_iam_role_policy" "ecs_deploy" {
  name = "ecs-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
}
