# mirra-infra

Infrastructure as code, CI/CD configuration, and operational documentation for the Mirra Trading platform.

## What's Here

- **Terraform** modules and environments for cloud infrastructure
- **CI/CD** workflows for the backend and frontend repos
- **Documentation** for architecture, runbooks, and onboarding
- **Operational scripts** for routine tasks

## Stack

- **Terraform** as the IaC tool (cloud provider TBC)
- **GitHub Actions** for CI/CD
- **PostgreSQL** as the application database

## Quick Start

This repo is an **M0 skeleton**: the Terraform structure and placeholder modules are in
place and validate cleanly, but no real cloud resources are defined yet. The cloud
provider and region are pending confirmation from Mirra Trading
(see `docs/provider-and-region.md`). Once selected, fill out the provider blocks in
`terraform/environments/dev/main.tf` and `terraform/environments/prod/main.tf` and
replace the placeholder module contents with provider-specific resources.

Requires Terraform `>= 1.5.0`. From a clean clone, verify the skeleton:

```bash
# Format check across all Terraform
terraform -chdir=terraform fmt -check -recursive

# Init + validate each environment (no backend/provider needed at M0)
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev validate

terraform -chdir=terraform/environments/prod init -backend=false
terraform -chdir=terraform/environments/prod validate
```

`terraform plan` / `apply` are intentionally not runnable yet — they become available
once the provider blocks and placeholder modules are filled in.

## Project Structure

```
mirra-infra/
├── terraform/
│   ├── modules/
│   │   ├── network/         # VPC, subnets, security groups
│   │   ├── database/        # Managed PostgreSQL
│   │   ├── api/             # Backend service (container/serverless)
│   │   └── frontend/        # Static hosting / CDN
│   └── environments/
│       ├── dev/
│       └── prod/
├── docs/                    # Architecture, runbooks, scope docs
├── scripts/                 # Operational helpers
├── .github/workflows/       # CI/CD reusable workflows
└── CLAUDE.md                # Conventions for AI assistants
```

## Related Repositories

- `mirra-backend` - Python FastAPI backend
- `mirra-frontend` - Next.js PWA frontend

## Notes

- The cloud provider has not been finalised. Modules in `terraform/modules/` currently contain placeholders and structural conventions; provider-specific resources will be filled in once the cloud is chosen.
- All documents shared with the client (scope, design brief, delivery assessment) live under `docs/`.
