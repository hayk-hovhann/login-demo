# One repository per service. MUTABLE so CD can move :latest; scan on push is
# ECR's free basic CVE scan. No repository policy: access is granted on the
# identity side, by the CD role (iam.tf) and the app's task execution role.
#
# prevent_destroy: a repository goes with its images, and every task start
# pulls from here.
resource "aws_ecr_repository" "service" {
  for_each = toset(["backend", "frontend"])

  name                 = "login-demo-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Cost hygiene: keep the 10 newest images, any tag, and expire the rest. The
# count is per repository, so backend's migrate-<sha> images share the 10 with
# its runtime images.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
