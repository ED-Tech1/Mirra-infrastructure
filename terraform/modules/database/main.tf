/**
 * Database module
 *
 * Managed PostgreSQL instance with backups and parameter groups appropriate
 * for the chosen cloud provider. Schema migrations are NOT managed here;
 * they are run by the backend pipeline using Alembic.
 *
 * Expected outputs:
 *   - host
 *   - port
 *   - database_name
 *   - secret_id (reference to the credentials in the secret manager)
 */

# Resources go here.
