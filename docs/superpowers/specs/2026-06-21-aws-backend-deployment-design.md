# AWS Backend Deployment — Design Spec

- **Date:** 2026-06-21
- **Repo:** `mirra-infra` (pushed to `github.com/ED-Tech1/Mirra-infrastructure`)
- **Status:** Approved design, pending implementation plan
- **Scope:** Provision and deploy the Mirra backend on AWS (eu-north-1) entirely via Terraform, with full CI/CD on the `mirra-backend` and `mirra-infra` repos. The frontend is deployed on Vercel and is out of scope for AWS hosting.

## 1. Context & Decisions

The Mirra platform has three repos:

- `mirra-backend` — FastAPI / Python 3.12, runs `uvicorn app.main:app` on `:8000`, exposes `/health`, uses Alembic migrations against PostgreSQL 16 (`psycopg`). It has a production boot-guard that refuses to start unless `SECRET_KEY`, `DATABASE_URL`, and a non-wildcard `ALLOWED_ORIGINS` are set, with `ENVIRONMENT=production`.
- `mirra-frontend` — Next.js 15 PWA, **deployed on Vercel** (not statically exportable; not hosted on AWS).
- `mirra-infra` — this repo. Terraform modules and environments were empty stubs prior to this work.

### Confirmed decisions

| Decision | Choice |
| --- | --- |
| Cloud provider / region | AWS, `eu-north-1` (Stockholm) |
| Compute | One EC2 `t3.micro` running the backend as a Docker container |
| Database | One RDS `db.t3.micro` PostgreSQL 16, private |
| Object storage | One private S3 bucket (forward-looking; backend has no S3 code yet) |
| HTTPS without a domain | CloudFront distribution in front of EC2, using the free `*.cloudfront.net` certificate |
| Frontend | Vercel; **not** managed by Terraform |
| Environments | Single environment, **no** dev/prod split |
| Terraform state | S3 bucket + DynamoDB lock table |
| Migrations during deploy | Run from GitHub Actions, over an SSM port-forward tunnel to keep RDS private |
| Backend deploy trigger | Auto on push to `main` |
| Infra deploy trigger | `plan` on PR, `apply` on push to `main` |
| Backend repo edits | New files only (`Dockerfile`, `.github/workflows/deploy.yml`); no edits to pre-existing files |

### Key constraint that drove the topology

The Vercel PWA is served over HTTPS and cannot call a plain-HTTP backend (browsers block mixed content). Without a registered domain, the clean way to give the EC2 backend HTTPS is to front it with CloudFront and use the default `*.cloudfront.net` certificate. That CloudFront URL becomes the frontend's `NEXT_PUBLIC_API_URL`.

## 2. Architecture

```
Internet ──HTTPS──▶ CloudFront (*.cloudfront.net, free cert, caching disabled)
                          │ origin: HTTP :80, SG locked to CloudFront prefix list
                          ▼
        VPC 10.0.0.0/16  (eu-north-1)
        ├── Public subnet  ──▶ EC2 t3.micro (Elastic IP)
        │                        └─ Docker container: uvicorn :8000 (published :80)
        │                        └─ instance role: ECR pull, Secrets read, S3, SSM
        └── Private subnets ──▶ RDS db.t3.micro Postgres 16 (no public access)

Vercel (frontend PWA) ──HTTPS──▶ CloudFront URL   [NEXT_PUBLIC_API_URL]
```

### CloudFront as reverse proxy

- Single custom origin: the EC2 instance's stable public DNS (stable because of the attached Elastic IP), origin protocol HTTP on port 80.
- Cache policy: `CachingDisabled` (managed). Origin request policy: `AllViewer` (managed) so `Authorization`, cookies, query strings, and the `Origin` header all pass through to the backend untouched. The backend's `CORSMiddleware` therefore handles CORS itself.
- Viewer protocol policy: `redirect-to-https`.
- No CloudFront health checking (single origin).

### Origin lock-down & access

- EC2 security group ingress on `:80` is restricted to AWS's managed prefix list `com.amazonaws.global.cloudfront.origin-facing`, so the instance is not openly reachable from the internet.
- **No inbound SSH.** Operator and CI access to the instance is via AWS Systems Manager (SSM) Session Manager only. The instance role includes `AmazonSSMManagedInstanceCore`.

### No ALB

A single `t3.micro` behind CloudFront is the cheapest path to HTTPS-without-a-domain. This is a deliberate single point of failure appropriate for the MVP, not a resilient production topology.

## 3. Terraform Layout

```
terraform/
├── bootstrap/          # one-time, local state: S3 state bucket + DynamoDB lock table
├── modules/
│   ├── network/        # VPC, public + private subnets, IGW, route tables, security groups
│   ├── database/       # RDS Postgres 16, DB subnet group, SG (private only)
│   ├── compute/        # EC2, EIP, instance profile, user_data, SG   (replaces old `api` stub)
│   ├── storage/        # private S3 bucket (+ CORS for future presigned uploads)
│   └── cdn/            # CloudFront distribution
└── environments/
    └── mirra/          # single live root: composes modules + ECR, Secrets Manager, IAM, OIDC
```

- The empty `terraform/environments/dev/`, `terraform/environments/prod/`, and `terraform/modules/frontend/` stubs are **removed** (no dev/prod split; frontend is on Vercel).
- A `versions.tf` pins `hashicorp/aws ~> 5.0` and `hashicorp/random`, sets region `eu-north-1`, and requires Terraform `>= 1.9.8` (matching the pinned CI version, which supports DynamoDB-based state locking).
- ECR repository, Secrets Manager secrets, IAM roles, and the GitHub OIDC providers/roles live in the `environments/mirra/` live root (small, environment-specific resources) rather than in dedicated modules.

### State bootstrap (chicken-and-egg)

`terraform/bootstrap/` creates the S3 state bucket (versioned, encrypted, public access blocked) and the DynamoDB lock table. It uses **local state** and is applied **manually, once**, before any CI run. Its state is not committed. Every other configuration uses the S3 backend with DynamoDB locking. This is documented in the repo README, not automated.

## 4. Secrets & Runtime Configuration

Created in **AWS Secrets Manager** by Terraform (never in code, per repo convention):

- `SECRET_KEY` — generated with `random_password` (32-byte hex equivalent).
- DB master password — generated with `random_password`; the full `DATABASE_URL` (`postgresql+psycopg://USER:PASS@<rds-endpoint>:5432/<db>`) is composed and stored as a secret.
- `ALLOWED_ORIGINS` — sourced from a Terraform variable (the Vercel production + preview domains) and stored as a secret, so it can change without re-provisioning infra.

### Instance bootstrap & runtime

EC2 `user_data`:

1. Installs Docker and enables the SSM agent (preinstalled on Amazon Linux 2023).
2. Installs a `systemd` unit (`mirra-backend.service`) that runs a `deploy.sh` wrapper.

`deploy.sh` (invoked at boot and on each deploy):

1. Authenticates to ECR via the instance role and pulls the `:latest` image.
2. Reads `SECRET_KEY`, `DATABASE_URL`, and `ALLOWED_ORIGINS` from Secrets Manager into `/etc/mirra/backend.env`.
3. Runs the container with `--env-file /etc/mirra/backend.env`, `ENVIRONMENT=production`, publishing container `:8000` as host `:80`.

This satisfies the backend's production boot-guard (`SECRET_KEY`, `DATABASE_URL`, non-wildcard `ALLOWED_ORIGINS`, `ENVIRONMENT=production` all present).

## 5. IAM

- **EC2 instance role:** ECR pull; `secretsmanager:GetSecretValue` scoped to the three secrets; read/write scoped to the single S3 storage bucket; `AmazonSSMManagedInstanceCore`; CloudWatch Logs write.
- **GitHub OIDC — backend deploy role:** assumed by `mirra-backend` `main`. Permissions: ECR push; `secretsmanager:GetSecretValue` for the DB secret (to run migrations); `ssm:StartSession` / `ssm:SendCommand` scoped to the instance; describe calls needed for those.
- **GitHub OIDC — infra role:** assumed by `mirra-infra` `main`. Permissions broad enough for `terraform apply` (VPC, EC2, RDS, IAM, CloudFront, S3, Secrets Manager, ECR), plus access to the state bucket and lock table. Scoped by OIDC subject to the `mirra-infra` repo and `main` branch.

Both OIDC roles trust `token.actions.githubusercontent.com` with `sub` conditions pinned to the specific repo and branch.

## 6. Storage

- Private S3 bucket: Block Public Access on, server-side encryption, versioning enabled.
- A CORS rule pre-configured for the Vercel origin (PUT/GET) so the backend can later issue presigned upload URLs for livestock images.
- The backend has **no S3 code today**; this provisions the bucket ahead of that feature. The instance role grants scoped read/write to this bucket only.

## 7. CI/CD

Three pipelines. Reusable workflows live in `mirra-infra/.github/workflows/reusable/`.

### 7.1 `mirra-backend` — build, migrate, deploy

New files in `mirra-backend` (new files only; no edits to existing files):

- **`Dockerfile`** — `python:3.12-slim`, installs `uv`, `uv sync`, runs `uvicorn app.main:app --host 0.0.0.0 --port 8000`.
- **`.github/workflows/deploy.yml`** — thin caller that `uses:` `ED-Tech1/Mirra-infrastructure/.github/workflows/reusable-backend-deploy.yml@main`.

The reusable backend deploy workflow runs on push to `main`, after the existing `reusable-backend-ci.yml` gate (lint / type-check / test) passes:

1. Assume the backend OIDC deploy role.
2. Build image, tag `:<git-sha>` and `:latest`, push to ECR.
3. **Migrate (on the runner):** start an SSM port-forward session EC2→RDS:5432 (`AWS-StartPortForwardingSessionToRemoteHost`), read DB creds from Secrets Manager, run `uv run alembic upgrade head` against `localhost:5432`, then close the tunnel. RDS stays private; `alembic` executes on the Actions runner.
4. **Deploy:** `ssm send-command` to the instance → `deploy.sh` pulls `:latest` and restarts `mirra-backend.service`.

Order matches the repo convention: infra (separate) → migrate → deploy.

### 7.2 `mirra-infra` — plan / apply

In `mirra-infra/.github/workflows/`:

- **On PR:** `terraform fmt -check`, `terraform validate`, `terraform plan` against the S3 backend; plan output surfaced on the run.
- **On push to `main`:** `terraform apply` (auto), using the infra OIDC role.

The pre-existing `terraform-ci.yml` (fmt/validate only) is superseded by the new plan/apply workflow.

### 7.3 Reusable workflows

`reusable-backend-deploy.yml` (used cross-repo by `mirra-backend`) and the infra plan/apply logic live here so both repos share a single source of truth.

## 8. Outputs Handed to Vercel

After `terraform apply` and the first backend deploy, the following are provided for the Vercel project:

- `NEXT_PUBLIC_API_URL = https://<distribution-id>.cloudfront.net` (the frontend strips any trailing `/api/v1`, so the bare origin is correct).
- `NEXT_PUBLIC_APP_NAME = Mirra Trading`.

The Vercel production and preview domains are set into the backend's `ALLOWED_ORIGINS` (the Terraform variable feeding the Secrets Manager value) so CORS works in both directions.

## 9. Git & Remote

`mirra-infra` is not currently a git repo. Implementation will `git init`, add the remote `github.com/ED-Tech1/Mirra-infrastructure`, commit, and push using the operator's local git/`gh` credentials. If the push is rejected for auth reasons, stop and hand back to the operator rather than guessing at credentials.

## 10. Out of Scope (deliberate)

- ALB / auto-scaling (single instance by choice).
- Custom domain / Route 53 / ACM (using CloudFront default cert).
- Multi-AZ RDS, read replicas, PITR tuning beyond defaults.
- WAF / Shield.
- S3 integration in the backend application code.
- Any Vercel resources in Terraform.
- dev/prod environment split.

All are natural follow-ups once the MVP is live.

## 11. Cost & Risk Notes

- **Cost:** EC2 `t3.micro` + RDS `db.t3.micro` + Elastic IP + minimal CloudFront/S3/Secrets Manager. Modest, and largely free-tier-eligible for the first 12 months.
- **Risk:** The single `t3.micro` is an intentional single point of failure for the MVP. No high availability. Acceptable for current scope; revisit before scaling.
