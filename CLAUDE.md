# CLAUDE.md - mirra-infra

This file gives Claude Code (and other AI assistants) the conventions and context for the Mirra Trading infrastructure repository. Read this before making changes.

## Project Overview

This repository holds infrastructure as code, CI/CD configuration, and operational documentation for the Mirra Trading platform. It does not contain application code; that lives in `mirra-backend` (Python API) and `mirra-frontend` (Next.js PWA).

The platform is for Mirra Trading, a halal meat export business operating between Ethiopia and Saudi Arabia. The MVP is a livestock inventory PWA with offline-first capability. See `docs/` for scope and architecture documents.

## Stack

- Terraform for IaC
- GitHub Actions for CI/CD
- PostgreSQL as the application database
- Cloud provider: pending confirmation from the client (placeholder modules in place until selected)

## Critical Conventions

### 1. Two Environments, Two Workspaces

- `dev` for the development environment.
- `prod` for production.

Each lives under `terraform/environments/<env>/` with its own state file. Do not share state between environments. State is stored in a remote backend (to be configured once the cloud provider is selected).

### 2. Modules Are Provider-Agnostic Where Possible

Modules under `terraform/modules/` describe the shape of resources (network, database, api, frontend) using variables. Environments compose modules and supply environment-specific values. When the cloud provider is finalised, provider-specific resources go into the modules, not the environments.

### 3. No Secrets in Code

Never commit secrets to this repo. Secrets are:

- Stored in the cloud provider's secret manager (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, etc.)
- Referenced by ARN/ID in Terraform
- Loaded at application runtime by the backend

For local development, secrets are in `.env` files in each app repo (gitignored).

### 4. Database Migrations Run Out-of-Band

Alembic migrations are run by the backend's CI/CD pipeline against the target database before deploying new application code. They are not run by Terraform. The order is:

1. Terraform applies infrastructure changes (including any database parameter group changes, but never schema changes).
2. The backend pipeline runs `alembic upgrade head` against the target database.
3. The new backend version is deployed.

### 5. Immutable Deployments

Backend and frontend deployments use immutable artefacts (container images, signed bundles). Updates roll forward with a new deployment, not by mutating existing infrastructure.

### 6. Environment Parity

`dev` mirrors `prod` in shape; the only differences are size and high-availability settings. This means surprises in production are minimised. Avoid using different services between environments (e.g. SQLite in dev, PostgreSQL in prod), the database engine must match.

### 7. Documentation Lives Here

Project-wide documents (scope, prototype briefs, delivery assessments, architecture notes, runbooks) live under `docs/`. Application-specific READMEs and `CLAUDE.md` files live in their respective application repos. When in doubt: cross-cutting goes here, app-specific goes there.

## Project Structure

```
terraform/
├── modules/
│   ├── network/             # VPC, subnets, routing, security groups
│   ├── database/            # Managed PostgreSQL with parameter groups and backup policy
│   ├── api/                 # Backend service (containers or serverless, TBC by provider)
│   └── frontend/            # Static hosting and CDN for the PWA
└── environments/
    ├── dev/                 # main.tf, variables.tf, terraform.tfvars
    └── prod/

docs/
├── mvp-scope.md             # MVP scope agreement
├── architecture.md          # System architecture overview
├── offline-sync.md          # Offline-first sync design
├── prototype-brief.md       # Prototype design brief
└── runbooks/                # Operational runbooks (per-environment)

scripts/
├── deploy/                  # Manual deployment helpers
└── ops/                     # Operational scripts (DB backup verification, etc.)

.github/workflows/
└── reusable/                # Reusable workflows referenced by app repos
```

## Things Not to Do

- Do not run `terraform apply` directly against production from a developer machine. Production changes flow through a CI workflow with approvals.
- Do not store state locally. Always use the remote backend.
- Do not commit `*.tfvars` files that contain real values. Only `*.tfvars.example` is committed.
- Do not put application schema migrations in Terraform. Schema lives in the backend repo.
- Do not modify `dev` to be lighter than `prod` in a way that hides bugs (different DB engine, different region behaviour, etc.).

## Pending Decisions

The following are not yet finalised and are blocking some of this repo:

- **Cloud provider**: needed before module internals can be written.
- **Hosting region**: needs Mirra Trading data residency confirmation.
- **Domain and TLS**: domain registration and certificate management approach.

Once these are confirmed, this `CLAUDE.md` will be updated with provider-specific conventions (e.g. naming, tagging, IAM patterns).

## Helpful References

- Terraform: https://developer.hashicorp.com/terraform/docs
- GitHub Actions: https://docs.github.com/en/actions
