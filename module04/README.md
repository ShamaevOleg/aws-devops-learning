# Module 04 — Containers on AWS: ECR and EKS

Building a private container registry with Terraform, then a Kubernetes cluster
to run images from it. This module connects the CI/CD work from Module 03 to
actual compute.

## What this module does

- Creates a private ECR repository with immutable tags, scan-on-push, and a
  lifecycle policy that keeps the registry from growing without limit.
- Extends the pipeline's IAM role with two separate ECR policies: one for
  managing the repository, one for pushing images.
- Provisions an EKS cluster with a dedicated VPC spanning two availability
  zones, a managed node group, and IAM-based access configured through Access
  Entries rather than the legacy `aws-auth` ConfigMap.

## Architecture

**Image flow:**
GitHub Actions builds an image → pushes to ECR (authenticated via the OIDC role
from Module 03) → EKS nodes pull the image using the node role's ECR
read permissions. Neither side stores registry credentials.

**Cluster layout:**
VPC `10.0.0.0/16` → two public subnets in different AZs → internet gateway and
route table → EKS control plane (managed by AWS) → managed node group running
EC2 workers.

## Key decisions

### ECS or EKS

ECS with Fargate is the simpler option: no control-plane cost, deep AWS
integration, and nothing to operate. EKS costs roughly $0.10 per hour for the
control plane and has more moving parts.

I chose EKS because the knowledge transfers. ECS concepts are AWS-specific,
while Kubernetes runs anywhere, and most platform engineering roles ask for it
directly. My existing Kubernetes experience is on-premise, so this closes the
gap between "runs Kubernetes" and "runs Kubernetes on a cloud provider."

### Immutable tags and no `latest`

The ECR repository is configured with immutable tags, so an existing tag cannot
be overwritten. Without this, an image tagged `v1.2.3` in the registry is not
guaranteed to be the same image that was deployed under that tag — the
reproducibility that tags are supposed to provide silently disappears.

Images are tagged with the git commit SHA. A tag then identifies exactly which
source produced the image, which `latest` never does.

### A lifecycle policy from the start

Every build adds an image, and stored images cost money. The policy keeps the
last 10 tagged images and expires untagged ones. The rule that matches all
tagged images uses `tagPatternList` with a wildcard, and it must have the
highest `rulePriority` in the set — a rule that matches everything will
short-circuit anything evaluated after it.

### Two ECR policies, not one

Managing the repository and pushing images to it are different concerns, so
they are separate policies on the role:

| Policy | Purpose |
|---|---|
| manage | create, describe, tag the repository; get, put and delete its lifecycle policy |
| push | authenticate to the registry, upload layers, put images |

`ecr:GetAuthorizationToken` is the one action that cannot be scoped to a
specific repository — the login token is issued for the whole registry, so its
resource is `*`. Everything else is scoped to `repository/*` in this account
and region, built from `aws_caller_identity` and `aws_region` rather than
hardcoded.

### Access Entries instead of `aws-auth`

EKS has two independent authorisation layers. IAM decides whether a principal
can call the EKS API at all; Kubernetes RBAC decides what that principal can do
inside the cluster. Being an administrator of the AWS account grants nothing
inside the cluster by itself.

The cluster uses `authentication_mode = "API"` with an explicit
`aws_eks_access_entry` and a policy association, rather than the older
`aws-auth` ConfigMap.

`bootstrap_cluster_creator_admin_permissions` is set to `false` deliberately.
When it is `true`, whoever ran `terraform apply` silently becomes a cluster
administrator — which means cluster access depends on whose credentials
happened to run the apply. Creating the cluster from a pipeline would grant
admin to the pipeline role and lock out the human operator. Declaring access
explicitly makes it reproducible.

### AL2023, not AL2

Amazon Linux 2 EKS-optimised AMIs reached end of support in November 2025, and
Kubernetes 1.32 was the last version they were published for. Node groups use
`AL2023_x86_64_STANDARD`, which also brings cgroup v2 — some Kubernetes
features, such as MemoryQoS, are unavailable on cgroup v1.

## Problems and solutions

### 1. Access policy association failed with a 404

**Symptom:** `ResourceNotFoundException: The specified principalArn could not be
found` when creating `aws_eks_access_policy_association`.

**Cause:** Two mistakes at once. The access entry had been created for the
cluster's service role, while the policy association referenced my IAM user —
so the association pointed at a principal that had never been registered.
Separately, both resources derived the principal ARN from the same data source
rather than from each other, so Terraform saw no dependency between them and
was free to create the association first.

**Fix:** Register the correct principal, and have the association reference
`aws_eks_access_entry.<name>.principal_arn` so the dependency is explicit.

**Takeaway:** An access entry registers *who* the cluster knows; the policy
association grants *what* they can do. The second cannot exist without the
first, and Terraform only knows that if the code says so.

### 2. Node group stuck in `CREATING` with no instances

**Symptom:** The node group sat in `CREATING` for over 20 minutes. `health`
reported no issues, no EC2 instances existed, and the `resources` and
`launchTemplate` fields in `describe-nodegroup` were empty.

**Cause:** Not visible until the capacity type was switched from `SPOT` to
`ON_DEMAND`, which produced the real error:

```
InvalidParameterCombination - The specified instance type is not
eligible for Free Tier.
```

The account is on the current AWS Free Tier free plan, which only permits
free-tier-eligible instance types. `t3.medium` is not one of them. With `SPOT`,
the auto scaling group retried the rejected launch indefinitely and surfaced no
error at all.

**Fix:** Queried the account for what it could actually launch —

```
aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true
```

— and used `c7i-flex.large`, `m7i-flex.large` and `t3.small`, all of which have
enough ENI capacity to run a useful number of pods.

**Takeaway:** A silent hang is often a retry loop hiding a rejection. Switching
to the simpler, more expensive path surfaced the error in one attempt. The
error message also named the exact command that would answer the question.

### 3. Pod density is limited by networking, not memory

The VPC CNI assigns every pod a real IP from the VPC, drawn from the elastic
network interfaces attached to the instance. How many ENIs and IPs an instance
supports is fixed by its type.

A `t3.micro` supports about four pods in total. The system DaemonSets and
CoreDNS consume that budget, leaving nothing for workloads — pods stay
`Pending` on a cluster that otherwise looks healthy.

Worth noting on the other side: `aws-node` and `kube-proxy` run with
`hostNetwork: true` and use the node's own IP, so they do not consume addresses
from the pool. Checking with `kubectl get pods -A -o wide` shows which pods hold
their own IP and which share the node's.

### 4. The console shows no nodes while `kubectl` does

**Symptom:** `kubectl get nodes` returned a `Ready` node; the EKS console's
node list for the same node group was empty.

**Cause:** The console reads Kubernetes objects through the cluster API, not
through the AWS API, so it needs the same RBAC access `kubectl` has. The access
entry was created for the principal used by the CLI, which was not the
principal signed in to the console.

**Takeaway:** A second, harmless demonstration of the IAM/RBAC split. When
something in EKS is not visible, the first question is which of the two layers
is refusing.

### 5. Interrupting `apply` left an unmanaged resource

**Symptom:** `terraform destroy -target=...` reported nothing to destroy, while
the node group still existed in AWS.

**Cause:** The apply had been cancelled while the node group was still
creating, so the resource was never recorded in state. Terraform no longer knew
it existed.

**Fix:** Deleted it directly with `aws eks delete-nodegroup`, then re-applied.

**Takeaway:** Cancelling an apply mid-flight is a reliable way to create drift.
Letting it fail on its own timeout leaves state consistent with reality.

## Known limitations / next steps

- **No image has been pushed through the pipeline yet.** The registry, the
  permissions and the node-side pull rights are in place, but the Dockerfile and
  the workflow that build and push are still to be written. Until then, the ECR
  pull path is untested end to end.
- **Nodes run in public subnets.** Acceptable for a short-lived learning
  cluster, but production nodes belong in private subnets with a NAT gateway or
  VPC endpoints, so workers are not directly reachable from the internet.
- **Cluster add-ons are implicit.** `vpc-cni`, `kube-proxy` and `coredns` are
  installed by EKS defaults rather than declared as `aws_eks_addon` resources,
  so their versions are not under version control.
- **The push policy is not scoped to a single repository.** It currently allows
  pushing to any repository in the account. With more than one service this
  should be narrowed so a pipeline cannot overwrite another service's images.
- **The cluster runs on the newest Kubernetes version available.** Production
  clusters usually track one version behind, giving add-ons and operators time
  to catch up.
