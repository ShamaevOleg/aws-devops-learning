locals {
  repositories = {
    backend = { name = "website/backend", scan_on_push = true, mutability = "IMMUTABLE" }
    demo    = { name = "website/demo", scan_on_push = false, mutability = "MUTABLE" }
  }
}

resource "aws_ecr_repository" "website" {
  for_each             = local.repositories
  name                 = each.value.name
  image_tag_mutability = each.value.mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = {
    Name = "repository:${each.value.name}"
  }
}

resource "aws_ecr_lifecycle_policy" "website_lc_policy" {
  for_each   = aws_ecr_repository.website
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"],
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}