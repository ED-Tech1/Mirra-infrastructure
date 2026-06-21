/**
 * API module
 *
 * Hosts the FastAPI backend. Deployment shape (container service, Kubernetes,
 * or serverless) is provider-dependent. Whichever shape, this module should:
 *   - Receive an immutable image/artefact reference as an input variable
 *   - Run the container with config from the secret manager
 *   - Expose a stable hostname for the frontend
 *   - Provide structured logs and basic metrics out of the box
 *
 * Migrations are NOT run from here. The deployment pipeline runs Alembic
 * against the database before flipping traffic to the new version.
 */

# Resources go here.
