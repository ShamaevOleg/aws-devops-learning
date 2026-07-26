# Module 02 — First Infrastructure with Terraform

Provisioning a working web server on AWS entirely from code: a VPC, a public
subnet, an internet gateway, routing, a security group, and an EC2 instance that
installs and serves nginx on boot. State lives remotely in S3 with locking, the
way it would in a team.

## What this module does

- Builds a VPC with a public subnet, an internet gateway, a route table, and a
  security group, then launches an EC2 instance into it.
- Installs nginx through `user_data` so the instance is serving a page as soon
  as it boots — no manual SSH step.
- Stores Terraform state in an S3 backend with native state locking, split into
  a `bootstrap/` step that creates the state bucket and an `infra/` step that
  uses it.

## Architecture

VPC `10.0.0.0/16` → public subnet → internet gateway → route table with a
default route to the gateway → security group (HTTP open, SSH restricted) →
EC2 instance running nginx, reachable on its public IP.

## The bootstrap problem

State should live in S3, but the S3 bucket itself has to be created by
Terraform — which needs somewhere to store its state before the bucket exists.
This is solved in two stages:

- `bootstrap/` creates the state bucket using local state, applied once.
- `infra/` configures the S3 backend pointing at that bucket, so all real
  infrastructure uses remote state from the start.

The state bucket has versioning enabled (so a corrupted state can be rolled
back), server-side encryption, and public access fully blocked.

## Key decisions

### What actually makes a subnet public

There is no `public = true` flag on a subnet in AWS. A subnet is public only
because the route table associated with it has a route sending `0.0.0.0/0` to an
internet gateway. Remove that route and the same subnet becomes private. The
instance also needs a public IP — assigned here via `map_public_ip_on_launch` —
because a route to the internet is useless without an address to be reached at.

### Finding the AMI instead of hardcoding it

The Ubuntu image is looked up with a `data` source filtered by name and owner,
not pinned to a fixed AMI ID. AMI IDs are region-specific and change every time
Canonical publishes a new image, so a hardcoded ID rots and breaks in other
regions. The owner is pinned to Canonical's account ID rather than an alias, so
the lookup can't accidentally match a lookalike image from another publisher.

### SSH scoped to one address

The security group opens HTTP to the world but restricts SSH to a single `/32` —
one IP address. New public IPs are scanned for open SSH within minutes, so a
`0.0.0.0/0` rule on port 22 invites brute-force attempts immediately. The
allowed address is a variable, never hardcoded into a public repository.

### Tags in one place

Common tags (`Project`, `ManagedBy`) are set once through the provider's
`default_tags` rather than repeated on every resource, so they can't drift out
of sync.

## Problems and solutions

### 1. `RouteNotSupported` when associating the route table

**Symptom:** `RouteNotSupported: Route table contains unsupported route
destination` when creating the route table association.

**Cause:** The association was written against the internet gateway
(`gateway_id`) instead of the subnet (`subnet_id`). That form is an *edge*
association, meant for routing traffic entering the VPC — and its route table
may only contain routes pointing inward, not a `0.0.0.0/0` route to the
internet.

**Fix:** Associate the route table with the subnet, using `subnet_id`. The two
arguments are mutually exclusive; the wrong one produced a valid-but-wrong
resource that AWS then rejected.

**Takeaway:** A route table association answers "which subnet uses this table,"
not "which gateway." Reaching for the gateway argument silently changed the
meaning.

### 2. The instance had no network references

**Symptom:** `apply` succeeded, but the instance was not on the VPC that had
just been built.

**Cause:** The `aws_instance` had no `subnet_id` and no security group
reference. With nothing tying it to the new network, AWS launched it into the
account's default VPC — leaving the hand-built VPC, subnet, and security group
sitting empty.

**Fix:** Reference the subnet and the security group explicitly. Resources are
linked by referencing each other's attributes; without those references
Terraform builds isolated pieces rather than connected infrastructure.

**Takeaway:** A set of resources is not infrastructure until they reference one
another. Drawing the arrows — who points at whom — reveals the ones that stand
alone.

### 3. The AMI lookup returned nothing

**Symptom:** The plan failed because the AMI `data` source matched no images.

**Cause:** The lookup filtered for image names beginning with `ubuntu/` but set
the owner to `amazon`. Official Ubuntu images are published by Canonical, not
Amazon, so the name and owner contradicted each other and nothing matched.

**Fix:** Set the owner to Canonical's account ID.

**Takeaway:** Pinning the image owner is both a correctness and a supply-chain
concern — it's what stops a lookup from resolving to someone else's lookalike
image.

### 4. `user_data` ran but nginx never started

**Symptom:** The instance booted, but nothing answered on port 80.

**Cause:** The `user_data` script had a blank line before the `#!/bin/bash`
shebang. cloud-init decides how to run the script from its first two
characters; with the shebang not on the first line, the script was never
executed as a shell script — silently, with no error.

**Fix:** Put the shebang on the very first line of the script.

**Takeaway:** `user_data` failures are quiet. When an instance boots but serves
nothing, `/var/log/cloud-init-output.log` on the box shows whether the script
ran at all.

## Known limitations / next steps

- **HTTP only.** The instance serves plain HTTP; the browser marks it "not
  secure." Production would terminate TLS, via an ACM certificate on a load
  balancer or a reverse proxy with automatic certificates.
- **A single subnet in one availability zone.** Fine for a single instance, but
  anything needing resilience requires subnets across multiple AZs — which is
  exactly what the EKS module later has to build.
- **Changes are applied by hand from a laptop.** Running `plan` and `apply`
  locally is the problem the next module solves by moving them into CI/CD.
