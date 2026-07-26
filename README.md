# aws-devops-learning

A hands-on AWS and Terraform project, built in the open one module at a time.
Each module solves a real problem end to end — infrastructure as code, CI/CD,
containers, and Kubernetes — and documents what broke along the way, not just
the finished result.

The focus is production practice rather than tutorials: remote state with
locking, keyless authentication via OIDC, least-privilege IAM, and approval-gated
deployments.

## Tech

Terraform · AWS (VPC, EC2, IAM, ECR, EKS, S3) · GitHub Actions · Docker · Kubernetes

## Repository layout

| Path | What's here |
|---|---|
| `module02/` | First infrastructure with Terraform: a VPC, public subnet, internet gateway, security group, and an EC2 instance serving nginx. Split into `bootstrap/` (creates the S3 bucket for remote state) and `infra/` (the infrastructure itself). |
| `module03/oidc/` | The OIDC trust foundation. Registers GitHub as an OIDC provider in AWS and defines the IAM roles the pipelines assume — applied once, by hand. |
| `module03/infra/` | A small VPC used as the subject of the CI/CD pipeline — the thing that gets planned and applied through GitHub Actions. |
| `module04/ecr/` | A private ECR container registry with immutable tags, scan-on-push, and a lifecycle policy. |
| `module04/eks/` | An EKS cluster: a dedicated VPC across two availability zones, a managed node group, and IAM access wired through EKS Access Entries. |
| `module04/app/` | A minimal container image (nginx) and its Dockerfile — the subject of the image-build pipeline. |
| `.github/workflows/` | The pipelines: `terraform-plan` and `terraform-apply` for infrastructure, and `image-build` for building and pushing the container image to ECR. |

Each module directory has its own `README.md` with the design decisions and a
"problems and solutions" section covering what went wrong and why.

## How authentication works

No AWS access keys are stored in GitHub. GitHub Actions authenticates to AWS
through OIDC federation: a workflow requests a short-lived token, and an IAM
role's trust policy decides whether to accept it based on which repository,
branch, or environment the run came from.

Three roles map to three concerns:

- **read-only** — broad trust, weak permissions; runs `terraform plan` on pull requests
- **apply** — narrow trust scoped to a protected environment; runs `terraform apply` after manual approval
- **ecr-push** — trust scoped to the `main` branch; pushes container images

## Modules

1. AWS account setup — IAM, MFA, CLI
2. First infrastructure with Terraform — VPC, EC2, nginx, remote state in S3
3. CI/CD for infrastructure — GitHub Actions, OIDC, plan on PR, gated apply on merge
4. Containers on AWS — ECR, EKS, and an image-build pipeline

Modules 5 onward continue toward deploying a real application on AWS.

## Notes

This is a learning repository. Some choices are deliberately simplified for cost
or clarity (public subnets for nodes, broad managed policies in places) and are
called out as such in each module's README under "known limitations."