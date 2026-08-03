# Module 06 — Containerising an Application for the Cloud

Preparing a Django backend to run on AWS, and connecting a separate application
repository to this infrastructure through a dedicated OIDC role.

The application code lives in a **private repository** (it belongs to a client),
so this README documents the architecture and the decisions rather than the
application itself. The only infrastructure change in this repo is the new IAM
role described below; everything else here is about *why* the pieces fit together
the way they do.

## The two-repository split

The application and the infrastructure live in separate repositories, on purpose:

- **application repo** (private) — the code, its Dockerfile, and a CI pipeline
  that builds an image and pushes it to ECR.
- **infrastructure repo** (this one, public) — the VPC, EKS, ECR, and RDS the
  application runs on.

This is a common production pattern, not a workaround. The two have different
lifecycles, different owners, and different rates of change. Mixing them means a
change to application code and a change to a network rule sit in the same history
and the same review; keeping them apart keeps each concern reviewable on its own.

The bridge between them is a single IAM role. The application's pipeline assumes
it through OIDC to push images — and can do nothing else, and touch no other
repository's images.

## Cross-repository OIDC

The pipelines in this repo authenticate to AWS as workflows from
`ShamaevOleg/aws-devops-learning`. The application's pipeline runs in a different
repository, so its OIDC token carries a different `sub` claim — and the existing
roles, whose trust policies name this repo, will not accept it.

So the application gets its own role, defined here in `module03/oidc/`:

- trust scoped to the application repository
- permissions limited to pushing images, and only to that application's
  namespace in ECR (`repository/website/*`), not the whole registry

The result: the application's CI can push its own images and nothing more. It
cannot read Terraform state, change infrastructure, or overwrite images that
belong to this repository's own pipelines. Least privilege across a trust
boundary — the application is trusted to do exactly one thing.

## Containerising Django for production

The backend previously ran on Django's development server. Moving it into a
container that runs on Kubernetes surfaced several things that "works on one
server" quietly depends on. These are general Django-on-Kubernetes concerns, not
specific to this application.

### The development server is not for production

`manage.py runserver` is single-threaded and explicitly not built for
production. In the container it is replaced by **gunicorn**, a WSGI server that
runs the app across several worker processes. Django already exposes a WSGI
entrypoint, so this changes how the app is *run*, not the app itself.

### Migrations must not run on container start

Running `migrate` as part of the container's start command works on a single
server. On Kubernetes, where several replicas start at once, every replica would
run migrations against the same database simultaneously — a race that can
deadlock or corrupt the schema.

Migrations belong in a **separate step** that runs once before the new replicas
roll out (a Job or an init container), not tied to the startup of every pod. The
start command was reduced to running gunicorn alone.

### A file-based cache doesn't survive multiple pods

The application used a file-based cache so that state (used by one-time
passwords) would be shared across gunicorn workers on one server. On Kubernetes
this breaks: each pod has its own filesystem, so a value written by one pod is
invisible to another. A code issued on one pod fails verification on the next.

The correct answer in the cloud is a cache all pods reach — **Redis**
(or ElastiCache). This is deferred to the deployment module, but the containerised
config is written expecting an external cache rather than a local directory.

### Static files at build time, media on object storage

Static files (CSS, JS, the admin interface) are collected into the image at
**build time**, so every pod ships identical, pre-built assets rather than
collecting them at start. WhiteNoise serves them from the app process, which is
acceptable in production.

User-uploaded media is different: it can't live in the container (pods are
ephemeral and don't share a filesystem) and belongs on **S3**. That is part of
the deployment module.

### Configuration from the environment

Twelve-factor configuration — reading settings from the environment rather than
hardcoding them — was already in place in this application, which made the move
straightforward. `DEBUG`, the secret key, database connection, and TLS-related
flags all come from environment variables, so the same image runs locally on a
SQLite fallback and in the cloud against PostgreSQL, with no code change.

### A leaner, safer image

The image is multi-stage: dependencies are installed in a build stage, and only
the installed packages are carried into the runtime stage. Because the database
driver and the imaging library both install from prebuilt wheels, no compiler is
needed in the final image at all — dropping it removed weight and attack surface,
taking the image from roughly 630 MB to 414 MB. The container also runs as a
non-root user, which Kubernetes security policies frequently require.

## CI: tests gate the build

The application's pipeline runs its test suite before building anything. The
build-and-push job depends on the test job, so an image is only produced if the
tests pass — a broken commit never reaches the registry. Only the build job holds
the OIDC permission to reach AWS; the test job has no cloud access at all.

The image is tagged with the commit SHA, so every image traces back to an exact
commit, and authentication to ECR is entirely through OIDC — no static AWS
credentials anywhere in the application repository.

## What this module changed here

- Added `github-iam-role-website-ecr-push` in `module03/oidc/` — a cross-repo
  OIDC role scoped to pushing the application's images.

Everything else — the container image and the CI pipeline — lives in the private
application repository and is described here only in principle.

## Deferred to Module 07 (deployment)

- Deploying the backend to EKS via GitOps (Argo CD)
- Reading the database password from Secrets Manager inside the cluster
- Replacing the file-based cache with Redis
- Running migrations as a pre-deploy Job
- Serving user media from S3
