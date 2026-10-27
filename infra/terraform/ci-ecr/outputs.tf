# The same three values the CloudFormation template output, for people at the
# terminal. No SSM parameters: no config or script reads these. CD has the
# role ARN in the repository variable AWS_ROLE_ARN, and the app finds its
# repositories by name.

output "backend_repo_uri" {
  description = "Backend ECR repository URI: the image base in CD and the task definitions."
  value       = aws_ecr_repository.service["backend"].repository_url
}

output "frontend_repo_uri" {
  description = "Frontend ECR repository URI."
  value       = aws_ecr_repository.service["frontend"].repository_url
}

output "github_actions_role_arn" {
  description = "Role CD assumes: the value of the repository variable AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}
