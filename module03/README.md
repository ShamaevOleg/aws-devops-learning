# Module 03 — CI/CD for Infrastructure with GitHub Actions and AWS OIDC

Implementing OIDC-based authentication between GitHub Actions and AWS,
and building a CI/CD pipeline for Terraform-managed infrastructure.

## What this module does

- Two GitHub Actions pipelines, triggered by pull requests and pushes to `main`.
- The first pipeline runs `terraform plan` and posts the output as a comment on the PR.
- The second pipeline runs `terraform apply` and provisions infrastructure in AWS.
- Both pipelines authenticate to AWS via OIDC, with no static credentials stored in GitHub.

## Architecture

**Pull request opened:**
PR → GitHub Actions triggered → OIDC authentication with AWS →
`terraform init` → `fmt -check` → `validate` → `plan` → output captured → comment posted on PR

**Push to `main`:**
Push → GitHub Actions triggered → waits for reviewer approval (GitHub Environment) →
OIDC authentication with AWS → `terraform init` → `fmt -check` → `validate` → `apply`

## Key decisions

### Why OIDC instead of long-lived access keys

OIDC issues short-lived tokens that expire within an hour. There are no static
credentials to store, rotate, or leak — nothing sensitive lives in GitHub Secrets,
and an exposed log cannot compromise the AWS account.

### Why two IAM roles instead of one

The two roles differ in both directions:

| Role | Trust scope | Permissions |
|---|---|---|
| `github-iam-role-readonly` | broad — any run from the repository | read-only + state access |
| `github-iam-role-apply` | narrow — only the `production` environment | can create infrastructure |

A role that can create and destroy resources must not be assumable from an
arbitrary branch. A role that can only read is safe to expose more widely.

### Why an environment-scoped `sub`

When a job declares `environment: production`, GitHub changes the `sub` claim
in the OIDC token from `repo:<owner>/<repo>:ref:refs/heads/main` to
`repo:<owner>/<repo>:environment:production`.

The apply role's trust policy requires that exact value. Since the environment
is protected by required reviewers, the role can only be assumed by a run that
has been manually approved — the approval gate and AWS access are bound together.

## Problems and solutions

### 1. `terraform plan` is not a read-only operation

**Symptom:** `AccessDenied: not authorized to perform: s3:PutObject on
".../terraform.tfstate.tflock"`

**Cause:** With an S3 backend and state locking enabled, Terraform writes a lock
object before reading the state — even during `plan`. `ReadOnlyAccess` does not
cover this.

**Fix:** A dedicated policy granting `s3:GetObject`, `s3:PutObject` and
`s3:DeleteObject` on the state objects, plus `s3:ListBucket` on the bucket itself.

### 2. A stuck state lock after a failed run

**Symptom:** `Error acquiring the state lock ... StatusCode: 412,
PreconditionFailed`, referencing a lock ID created by an earlier run.

**Cause:** The previous run acquired the lock but could not release it, because
the role was missing `s3:DeleteObject`. The lock object stayed in the bucket.
On the next run Terraform tried to create the lock with a conditional
`PutObject` (write only if the object does not exist), and the precondition
failed because the stale lock was still there.

**Fix:** Added `s3:DeleteObject` to the state policy and cleared the stale lock
with `terraform force-unlock <lock-id>`.

**Takeaway:** An insufficient permission did not just fail one run — it left the
state locked and blocked every subsequent run. Pipeline permissions are worth
verifying up front rather than discovering them one error at a time.

### 3. The plan appeared twice in the PR comment

**Symptom:** The comment contained the plan output twice, along with internal
markers such as `stdout<<ghadelimiter_...`, `stderr<<...` and `exitcode<<...`.

**Cause:** `hashicorp/setup-terraform` enables a wrapper around the Terraform
binary by default (`terraform_wrapper: true`). The wrapper already captures
`stdout`, `stderr` and the exit code and exposes them as step outputs. The
workflow was also capturing the output manually with a heredoc redirect into
`$GITHUB_OUTPUT`, so the plan was collected twice.

**Fix:** Removed the manual redirect and relied on the wrapper's own
`steps.<id>.outputs.stdout`. The alternative would have been to disable the
wrapper with `terraform_wrapper: false` and keep the manual capture — either
approach works, but not both at once.
