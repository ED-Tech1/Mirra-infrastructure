# AWS Deployment Runbook

One-time setup, then everything runs through CI.

## 1. Bootstrap remote state (manual, once)

```bash
cd terraform/bootstrap
terraform init
terraform apply        # creates mirra-tfstate-<account-id> and mirra-tflocks
```

## 2. Configure the live backend

```bash
cd ../environments/mirra
cp backend.hcl.example backend.hcl   # set bucket = mirra-tfstate-<account-id>
cp terraform.tfvars.example terraform.tfvars  # set allowed_origins (Vercel domains), repos
terraform init -backend-config=backend.hcl
terraform apply
```

## 3. Wire CI secrets (from terraform outputs)

```bash
terraform output backend_deploy_role_arn   # -> backend repo (ED-Tech1/Mira-repo) secret AWS_DEPLOY_ROLE_ARN
terraform output infra_deploy_role_arn      # -> this repo (ED-Tech1/Mirra-infrastructure) secret TF_INFRA_ROLE_ARN
```

Set those as GitHub Actions repository secrets in each repo. Commit `backend.hcl`
(it holds only the bucket/table names, no secrets) so the infra CI can init.

## 4. Hand the frontend team their Vercel env

```bash
terraform output vercel_env
# NEXT_PUBLIC_API_URL  = https://<dist>.cloudfront.net
# NEXT_PUBLIC_APP_NAME = Mirra Trading
```

After the frontend is live, add its real Vercel domain(s) to `allowed_origins`
in `terraform.tfvars` and re-apply so backend CORS accepts them.

## 5. Trigger the first backend deploy

Only after steps 2–3 (apply done, `AWS_DEPLOY_ROLE_ARN` secret set on the backend
repo): push the backend repo (`ED-Tech1/Mira-repo`) `main`, or re-run its `deploy`
workflow. It builds the image, runs `alembic upgrade head` over the SSM tunnel, and
starts the container. Verify: `curl https://<dist>.cloudfront.net/health`.

> Note: between `terraform apply` and the first successful backend deploy, the
> EC2 container does not exist yet, so the CloudFront URL returns 5xx/connection
> errors. This is expected — the first `deploy` workflow run is what starts the
> service. Don't treat health-check failures in that window as breakage.
