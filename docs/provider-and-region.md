# Cloud Provider and Region — Pending Confirmation

**Status: BLOCKED on command-center confirmation. No provider or region has been selected.**

This repository is an M0 infrastructure *skeleton*. It establishes the Terraform
structure (root environments + placeholder modules) and validates cleanly, but it does
**not** provision any real cloud resources.

Two decisions are still pending and must be confirmed before module internals can be
written:

| Decision | Status | Why it is blocked |
|----------|--------|-------------------|
| **Cloud provider** (AWS / GCP / Azure / other) | Pending | Determines provider blocks, module resource types, IAM model, secret manager, and remote backend. |
| **Hosting region** | Pending | Requires Mirra Trading data-residency confirmation (Ethiopia / Saudi Arabia operations). |

Deliberately **not** chosen here. Picking either before sign-off would bake an
assumption into the skeleton that may be wrong.

## What unblocks when these are confirmed

1. Add the provider block(s) and `required_providers` in
   `terraform/environments/dev/main.tf` and `terraform/environments/prod/main.tf`.
2. Configure the remote backend (state locking on prod).
3. Replace the placeholder bodies in `terraform/modules/*/main.tf` with
   provider-specific resources, wiring up the already-stubbed variables and outputs.
4. Set a real value for the `region` variable (currently `FILL_ME_IN` in the
   `terraform.tfvars.example` files).

Until then, the placeholders are intentional and the skeleton is the deliverable.
