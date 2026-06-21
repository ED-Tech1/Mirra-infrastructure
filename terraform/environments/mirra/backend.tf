terraform {
  backend "s3" {
    # Values supplied via -backend-config=backend.hcl (see backend.hcl.example).
    # Partial config keeps the account-specific bucket name out of source.
  }
}
