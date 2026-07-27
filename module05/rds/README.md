# Module 05 — Managed Database: RDS PostgreSQL in a Private Network

Provisioning a PostgreSQL database on RDS the way it belongs in production:
in private subnets with no route to the internet, reachable only from the
application, with a master password that never appears in code or state.

This is the last of the foundation modules and prepares the data tier for the
REMNI ATELIER application deployed in later modules.

## What this module does

- Builds a VPC with two private subnets across availability zones and a DB
  subnet group spanning both.
- Creates two security groups: one for the application (empty, used as an
  identity) and one for the database that only accepts connections from the
  application group.
- Provisions a `db.t3.micro` PostgreSQL instance that is not publicly
  accessible, with its master password generated and stored by RDS in Secrets
  Manager.

## Architecture

VPC `10.0.0.0/16` → two private subnets (`10.0.10.0/24`, `10.0.11.0/24`) in
different AZs → DB subnet group → RDS PostgreSQL instance. No internet gateway,
no route out. The database is reachable only from within the VPC, and only by
resources in the application security group.

## Key decisions

### A private subnet is one without a route out

The subnets here differ from the public ones in earlier modules in exactly one
way: their route table has no `0.0.0.0/0` route to an internet gateway. Module 2
made a subnet public by adding that route; this module makes subnets private by
leaving it out. The VPC's default local route is enough for resources inside the
VPC to reach each other, which is all the database needs.

### Access by security group membership, not by IP

The database security group allows inbound traffic on port 5432 not from a CIDR
range, but from the *application security group*. The rule reads as "allow
connections from anything that belongs to the app security group."

This is better than a CIDR rule because it survives change: the application can
be recreated, rescaled, or given new IPs, and the rule keeps working, because it
is tied to group membership rather than to an address. The application security
group has no rules of its own at this stage — it exists purely as an identity to
be referenced.

### Two subnets for a single instance

A DB subnet group requires subnets in at least two availability zones, even when
the instance is single and Multi-AZ is off. AWS needs a place ready in a second
zone in case a failover or read replica is ever needed — the same reasoning that
made the EKS control plane require two subnets.

### The master password never touches code or state

Writing a password into Terraform leaks it twice: into state (stored in S3) and
into git. This module uses `manage_master_user_password = true`, which has RDS
generate the password itself, store it in Secrets Manager, and encrypt it with a
KMS key. Terraform only ever sees the secret's ARN, never the password. The
application will later read it from Secrets Manager by IAM permission, the same
pattern as dynamic credentials from Vault — an application reads a secret at
runtime instead of having it baked into configuration.

### `publicly_accessible = false`, set explicitly

RDS can assign a public endpoint to an instance, which would defeat the entire
point of the private subnets. This is set to `false` explicitly rather than left
to a default, so the database is only resolvable and reachable inside the VPC.

## Verification

The instance's endpoint is an internal DNS name that only resolves within the
VPC. Confirmed with:

```
aws rds describe-db-instances \
  --db-instance-identifier db-instance-for-backend \
  --query 'DBInstances[0].{public:PubliclyAccessible,status:DBInstanceStatus}'
```

returning `public: false`, `status: available`. Connecting from outside is not
possible by design; a real connection test happens in a later module, from an
application running inside the VPC.

## Known limitations / next steps

- **Single-AZ instance.** The subnet group spans two zones, but the instance
  itself is single-AZ. Production would enable Multi-AZ for automatic failover;
  it is left off here to stay within free-tier cost.
- **`skip_final_snapshot = true`.** Fine for a learning stand where the data is
  disposable, but production must take a final snapshot on deletion so data is
  not lost.
- **No automated password rotation configured.** RDS-managed secrets support
  rotation, which a production setup would enable; here the generated password
  is simply stored.
- **The application security group is empty.** It exists only to be referenced
  by the database. Its own inbound rules (for the app's HTTP port) are added
  when there is an application to protect.