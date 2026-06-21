# Mirra Trading Platform - Documentation

This directory holds cross-cutting documentation for the Mirra Trading platform. Application-specific docs live in their respective application repositories (`mirra-backend`, `mirra-frontend`).

## Index

### Scope and Planning

- `mvp-scope.md` - MVP scope, in-scope and out-of-scope capabilities, sign-off
- `prototype-brief.md` - Design brief for the meeting prototype
- `delivery-readiness.md` - Assessment of what can be built without pending client inputs, and the 6-week timeline
- `provider-and-region.md` - Cloud provider and hosting region are pending command-center confirmation (neither has been selected)

### Architecture

- `architecture.md` - System architecture overview (to be written)
- `offline-sync.md` - Offline-first sync design, conflict resolution, ear tag allocation (to be written)
- `data-model.md` - Core entity relationships (to be written)

### Operations

- `runbooks/` - Per-environment operational runbooks (to be added)
- `incident-response.md` - Incident response playbook (to be added)

## Conventions for Documents Here

- Markdown for technical docs, Word docs for client-facing deliverables.
- Documents intended for the client live in `docs/client/` and are versioned.
- Internal-only documents live at the root of `docs/`.
- Keep secrets, credentials, and customer-identifying details out of this repo.

## Related Repositories

- `mirra-backend` - Python FastAPI backend
- `mirra-frontend` - Next.js Progressive Web App
- `mirra-infra` (this repo) - Infrastructure as code and CI/CD
