# AWS Backend Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision the Mirra backend on AWS eu-north-1 (EC2 + RDS + S3 + CloudFront) entirely in Terraform, with auto-deploy CI/CD on `mirra-backend` and plan/apply CI/CD on `mirra-infra`.

**Architecture:** A single live Terraform root (`terraform/environments/mirra`) composes five modules (network, database, compute, storage, cdn) plus ECR, Secrets Manager, and GitHub OIDC roles. The backend runs as a Docker container on one EC2 `t3.micro`, fronted by CloudFront for HTTPS-without-a-domain. RDS stays private; migrations run from GitHub Actions over an SSM port-forward tunnel.

**Tech Stack:** Terraform `>= 1.9.8`, AWS provider `~> 5.0`, GitHub Actions, Docker, `uv`/FastAPI (backend), Amazon Linux 2023, SSM.

## Global Constraints

- **Region:** `eu-north-1`. **Single environment** named `mirra` — no dev/prod split.
- **Terraform:** `required_version >= 1.9.8`; providers `hashicorp/aws ~> 5.0`, `hashicorp/random ~> 3.6`, `hashicorp/tls ~> 4.0`.
- **No secrets in code.** `SECRET_KEY` and DB password are generated with `random_password`; values live only in AWS Secrets Manager. No `*.tfvars` with real values committed (`*.tfvars.example` only).
- **No local Terraform state** for the live root: S3 backend + DynamoDB lock. The `bootstrap/` config is the one exception (local state, applied manually once).
- **`mirra-backend` edits: NEW FILES ONLY.** Create `Dockerfile` and `.github/workflows/deploy.yml`. Do **not** modify any pre-existing backend file. If something seems to require editing an existing file, STOP and flag it.
- **Backend boot-guard:** the container must start with `ENVIRONMENT=production`, a non-default `SECRET_KEY`, a real `DATABASE_URL`, and a non-wildcard `ALLOWED_ORIGINS` (no `*`, no `localhost`).
- **Resource naming:** `${project}-${environment}-<thing>` where `project=mirra`, `environment=mirra` (so e.g. the EC2 `Name` tag is `mirra-mirra-api`).
- **No `apply` from a dev machine** except the one-time `bootstrap/`. All other applies go through CI.

---

## File Structure

```
terraform/
├── bootstrap/
│   ├── main.tf              # S3 state bucket + DynamoDB lock table (LOCAL state)
│   ├── variables.tf
│   └── outputs.tf
├── modules/
│   ├── network/   {main,variables,outputs}.tf
│   ├── database/  {main,variables,outputs}.tf
│   ├── compute/   {main,variables,outputs}.tf + user_data.sh.tftpl
│   ├── storage/   {main,variables,outputs}.tf
│   └── cdn/       {main,variables,outputs}.tf
└── environments/
    └── mirra/
        ├── versions.tf      # required_version + providers + region
        ├── backend.tf       # S3 backend (partial config)
        ├── backend.hcl.example
        ├── variables.tf
        ├── secrets.tf       # ECR, random_password, Secrets Manager
        ├── iam.tf           # GitHub OIDC provider + deploy roles
        ├── main.tf          # module wiring + secret versions
        ├── outputs.tf
        └── terraform.tfvars.example

.github/workflows/
├── terraform.yml                 # infra plan (PR) / apply (push main)
└── reusable-backend-deploy.yml   # called cross-repo by mirra-backend

# REMOVED: terraform/environments/dev, terraform/environments/prod,
#          terraform/modules/frontend, .github/workflows/terraform-ci.yml,
#          .github/workflows/reusable-terraform.yml, reusable-frontend-ci.yml

# mirra-backend (NEW FILES ONLY):
Dockerfile
.github/workflows/deploy.yml
```

**Verification model (infra adaptation of TDD):** Terraform has no unit-test cycle, so each module/config task's "test" is `terraform fmt` + `terraform init -backend=false` + `terraform validate` run in that directory. `validate` performs no AWS calls (data sources are not read), so it runs without credentials. Workflow YAML is checked with `actionlint` when available. The whole-system integration check is `validate` of the live root in Task 11.

---

### Task 1: Repo scaffolding — git init, prune stubs, live-root versions

**Files:**
- Create: `terraform/environments/mirra/versions.tf`
- Create: `terraform/environments/mirra/backend.tf`
- Create: `terraform/environments/mirra/backend.hcl.example`
- Delete: `terraform/environments/dev/`, `terraform/environments/prod/`, `terraform/modules/frontend/`
- Delete: `.github/workflows/terraform-ci.yml`, `.github/workflows/reusable-terraform.yml`, `.github/workflows/reusable-frontend-ci.yml`

**Interfaces:**
- Produces: the live-root provider config (region `var.region`, default tags) and the S3 backend partial config consumed by every later live-root task.

- [ ] **Step 1: Initialize git and add the remote**

```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-infra
git init
git branch -M main
git remote add origin https://github.com/ED-Tech1/Mirra-infrastructure.git
```

- [ ] **Step 2: Remove the stale stubs (no longer match the design)**

```bash
git rm -r --ignore-unmatch terraform/environments/dev terraform/environments/prod terraform/modules/frontend 2>/dev/null || true
rm -rf terraform/environments/dev terraform/environments/prod terraform/modules/frontend
rm -f .github/workflows/terraform-ci.yml .github/workflows/reusable-terraform.yml .github/workflows/reusable-frontend-ci.yml
```

- [ ] **Step 3: Write `terraform/environments/mirra/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9.8"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

- [ ] **Step 4: Write `terraform/environments/mirra/backend.tf` (partial config — values supplied at init)**

```hcl
terraform {
  backend "s3" {
    # Values supplied via -backend-config=backend.hcl (see backend.hcl.example).
    # Partial config keeps the account-specific bucket name out of source.
  }
}
```

- [ ] **Step 5: Write `terraform/environments/mirra/backend.hcl.example`**

```hcl
bucket         = "mirra-tfstate-<AWS_ACCOUNT_ID>"
key            = "mirra/terraform.tfstate"
region         = "eu-north-1"
dynamodb_table = "mirra-tflocks"
encrypt        = true
```

- [ ] **Step 6: Verify formatting**

Run: `terraform fmt -check -recursive terraform/`
Expected: exit 0 (no files reformatted). If it lists files, run `terraform fmt -recursive terraform/` and re-check.

- [ ] **Step 7: Commit**

```bash
git add terraform/environments/mirra/versions.tf terraform/environments/mirra/backend.tf terraform/environments/mirra/backend.hcl.example
git add -A
git commit -m "chore: init git, prune stale stubs, add live-root provider+backend config"
```

---

### Task 2: Bootstrap config (Terraform state bucket + lock table)

**Files:**
- Create: `terraform/bootstrap/main.tf`
- Create: `terraform/bootstrap/variables.tf`
- Create: `terraform/bootstrap/outputs.tf`

**Interfaces:**
- Produces: an S3 bucket named `mirra-tfstate-<account-id>` and DynamoDB table `mirra-tflocks`, referenced by the live root's `backend.hcl`.

- [ ] **Step 1: Write `terraform/bootstrap/variables.tf`**

```hcl
variable "project" {
  type    = string
  default = "mirra"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}
```

- [ ] **Step 2: Write `terraform/bootstrap/main.tf`**

```hcl
terraform {
  required_version = ">= 1.9.8"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # Intentionally LOCAL state: this config creates the bucket that all other
  # configs use as their backend. Applied manually, once. Do not commit its state.
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = "${var.project}-tflocks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

- [ ] **Step 3: Write `terraform/bootstrap/outputs.tf`**

```hcl
output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.locks.name
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/bootstrap && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Format and commit**

```bash
terraform fmt terraform/bootstrap/
git add terraform/bootstrap/
git commit -m "feat: add Terraform state bootstrap (S3 bucket + DynamoDB lock)"
```

---

### Task 3: Network module (VPC, subnets, routing)

**Files:**
- Create: `terraform/modules/network/main.tf` (overwrites the empty stub)
- Create: `terraform/modules/network/variables.tf`
- Create: `terraform/modules/network/outputs.tf`

**Interfaces:**
- Produces:
  - `output "vpc_id"` → string
  - `output "public_subnet_ids"` → list(string)
  - `output "private_subnet_ids"` → list(string)
- Consumes (inputs): `project`, `environment` (strings); `cidr_block` (string, default `10.0.0.0/16`); `az_count` (number, default `2`).

- [ ] **Step 1: Write `terraform/modules/network/variables.tf`**

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}
```

- [ ] **Step 2: Write `terraform/modules/network/main.tf`**

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-${var.environment}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-${var.environment}-igw" }
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-${var.environment}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 100)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.project}-${var.environment}-private-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.project}-${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

Note: no NAT gateway (cost). RDS is in private subnets with no egress need; EC2 sits in a public subnet with a public IP and reaches ECR/Secrets/SSM through the IGW. Two AZs are required because the RDS DB subnet group needs subnets in ≥2 AZs even for a single instance.

- [ ] **Step 3: Write `terraform/modules/network/outputs.tf`**

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/network && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Format and commit**

```bash
terraform fmt terraform/modules/network/
git add terraform/modules/network/
git commit -m "feat(network): VPC with public/private subnets across 2 AZs"
```

---

### Task 4: Storage module (private S3 bucket)

**Files:**
- Create: `terraform/modules/storage/main.tf`
- Create: `terraform/modules/storage/variables.tf`
- Create: `terraform/modules/storage/outputs.tf`

**Interfaces:**
- Produces:
  - `output "bucket_id"` → string
  - `output "bucket_arn"` → string
- Consumes: `project`, `environment` (strings); `bucket_suffix` (string, used to make the name globally unique — the AWS account id); `allowed_origins` (list(string), for CORS).

- [ ] **Step 1: Write `terraform/modules/storage/variables.tf`**

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_suffix" {
  type        = string
  description = "Suffix to make the bucket name globally unique (AWS account id)."
}

variable "allowed_origins" {
  type        = list(string)
  description = "Origins allowed for presigned-upload CORS (the Vercel domains)."
  default     = []
}
```

- [ ] **Step 2: Write `terraform/modules/storage/main.tf`**

```hcl
resource "aws_s3_bucket" "this" {
  bucket = "${var.project}-${var.environment}-storage-${var.bucket_suffix}"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT"]
    allowed_origins = var.allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
```

- [ ] **Step 3: Write `terraform/modules/storage/outputs.tf`**

```hcl
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/storage && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Format and commit**

```bash
terraform fmt terraform/modules/storage/
git add terraform/modules/storage/
git commit -m "feat(storage): private S3 bucket with CORS for future presigned uploads"
```

---

### Task 5: Database module (RDS PostgreSQL 16)

**Files:**
- Create: `terraform/modules/database/main.tf` (overwrites the empty stub)
- Create: `terraform/modules/database/variables.tf`
- Create: `terraform/modules/database/outputs.tf`

**Interfaces:**
- Produces:
  - `output "endpoint"` → string in the form `host:5432`
  - `output "db_security_group_id"` → string
- Consumes: `project`, `environment`; `vpc_id`; `private_subnet_ids` (list(string)); `app_security_group_id` (the EC2 SG allowed to connect); `instance_class` (default `db.t3.micro`); `engine_version` (default `"16"`); `allocated_storage` (default `20`); `db_name` (default `mirra`); `db_username` (default `mirra`); `db_password` (sensitive).

- [ ] **Step 1: Write `terraform/modules/database/variables.tf`**

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type        = string
  description = "Security group of the app instance permitted to reach Postgres."
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "mirra"
}

variable "db_username" {
  type    = string
  default = "mirra"
}

variable "db_password" {
  type      = string
  sensitive = true
}
```

- [ ] **Step 2: Write `terraform/modules/database/main.tf`**

```hcl
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.project}-${var.environment}-db-subnets" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "Postgres access from the app instance only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from app instance"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-db-sg" }
}

resource "aws_db_instance" "this" {
  identifier              = "${var.project}-${var.environment}-db"
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  storage_encrypted       = true
  multi_az                = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  apply_immediately       = true
  tags                    = { Name = "${var.project}-${var.environment}-db" }
}
```

- [ ] **Step 3: Write `terraform/modules/database/outputs.tf`**

```hcl
output "endpoint" {
  description = "Connection endpoint in host:port form."
  value       = aws_db_instance.this.endpoint
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/database && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Format and commit**

```bash
terraform fmt terraform/modules/database/
git add terraform/modules/database/
git commit -m "feat(database): private RDS Postgres 16 with app-only ingress"
```

---

### Task 6: Compute module (EC2 + EIP + instance role + user_data)

**Files:**
- Create: `terraform/modules/compute/main.tf` (overwrites the old `api` stub if present; this is the new module dir)
- Create: `terraform/modules/compute/variables.tf`
- Create: `terraform/modules/compute/outputs.tf`
- Create: `terraform/modules/compute/user_data.sh.tftpl`

**Interfaces:**
- Produces:
  - `output "instance_id"` → string
  - `output "instance_public_dns"` → string (the EIP's stable public DNS, used as the CloudFront origin)
  - `output "security_group_id"` → string (consumed by the database module as `app_security_group_id`)
- Consumes: `project`, `environment`, `region`; `vpc_id`; `public_subnet_id` (single string); `instance_type` (default `t3.micro`); `ecr_repository_url` (string); `storage_bucket_arn` (string); `secret_arns` (map(string) with keys `secret_key`, `database_url`, `allowed_origins`).

- [ ] **Step 1: Write `terraform/modules/compute/variables.tf`**

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ecr_repository_url" {
  type = string
}

variable "storage_bucket_arn" {
  type = string
}

variable "secret_arns" {
  type        = map(string)
  description = "Map with keys: secret_key, database_url, allowed_origins."
}
```

- [ ] **Step 2: Write `terraform/modules/compute/user_data.sh.tftpl`**

```bash
#!/bin/bash
set -euo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker

mkdir -p /etc/mirra /opt/mirra

cat > /etc/mirra/deploy.env <<EOF
AWS_REGION=${region}
ECR_REPOSITORY_URL=${ecr_repository_url}
SECRET_KEY_ARN=${secret_key_arn}
DATABASE_URL_ARN=${database_url_arn}
ALLOWED_ORIGINS_ARN=${allowed_origins_arn}
EOF

cat > /opt/mirra/deploy.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
source /etc/mirra/deploy.env

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$${ECR_REPOSITORY_URL%/*}"

docker pull "$ECR_REPOSITORY_URL:latest"

SECRET_KEY=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$SECRET_KEY_ARN" --query SecretString --output text)
DATABASE_URL=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$DATABASE_URL_ARN" --query SecretString --output text)
ALLOWED_ORIGINS=$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$ALLOWED_ORIGINS_ARN" --query SecretString --output text)

cat > /etc/mirra/backend.env <<ENVEOF
ENVIRONMENT=production
LOG_LEVEL=INFO
SECRET_KEY=$SECRET_KEY
DATABASE_URL=$DATABASE_URL
ALLOWED_ORIGINS=$ALLOWED_ORIGINS
ENVEOF
chmod 600 /etc/mirra/backend.env

docker rm -f mirra-backend 2>/dev/null || true
docker run -d --name mirra-backend --restart unless-stopped \
  --env-file /etc/mirra/backend.env \
  -p 80:8000 \
  "$ECR_REPOSITORY_URL:latest"
SCRIPT
chmod +x /opt/mirra/deploy.sh

cat > /etc/systemd/system/mirra-backend.service <<'UNIT'
[Unit]
Description=Mirra backend (pull latest image and run)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/mirra/deploy.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable mirra-backend.service
# Best-effort on first boot: the image won't exist until the first CI deploy.
systemctl start mirra-backend.service || true
```

Note on escaping: inside a Terraform `templatefile`, a literal `${` must be written `$${`. The only place the shell needs `${...}` literally is the `$${ECR_REPOSITORY_URL%/*}` parameter expansion; everything else uses `$VAR` which Terraform passes through untouched. The `${region}`, `${ecr_repository_url}`, `${secret_key_arn}`, `${database_url_arn}`, `${allowed_origins_arn}` tokens ARE the Terraform template variables.

- [ ] **Step 3: Write `terraform/modules/compute/main.tf`**

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "HTTP from CloudFront origin-facing ranges only; no inbound SSH"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-ec2-sg" }
}

resource "aws_iam_role" "instance" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance" {
  name = "${var.project}-${var.environment}-ec2-policy"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid      = "SecretsRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = values(var.secret_arns)
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [var.storage_bucket_arn, "${var.storage_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.instance.name
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region              = var.region
    ecr_repository_url  = var.ecr_repository_url
    secret_key_arn      = var.secret_arns["secret_key"]
    database_url_arn    = var.secret_arns["database_url"]
    allowed_origins_arn = var.secret_arns["allowed_origins"]
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-${var.environment}-api" }
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"
  tags     = { Name = "${var.project}-${var.environment}-eip" }
}
```

- [ ] **Step 4: Write `terraform/modules/compute/outputs.tf`**

```hcl
output "instance_id" {
  value = aws_instance.this.id
}

output "instance_public_dns" {
  description = "Stable public DNS of the Elastic IP; used as the CloudFront origin."
  value       = aws_eip.this.public_dns
}

output "security_group_id" {
  value = aws_security_group.ec2.id
}
```

- [ ] **Step 5: Validate**

Run: `cd terraform/modules/compute && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Format and commit**

```bash
terraform fmt terraform/modules/compute/
# remove the old api stub directory if it still exists
git rm -r --ignore-unmatch terraform/modules/api 2>/dev/null || true
rm -rf terraform/modules/api
git add terraform/modules/compute/
git commit -m "feat(compute): EC2 t3.micro with EIP, instance role, and Docker user_data"
```

---

### Task 7: CDN module (CloudFront reverse proxy)

**Files:**
- Create: `terraform/modules/cdn/main.tf`
- Create: `terraform/modules/cdn/variables.tf`
- Create: `terraform/modules/cdn/outputs.tf`

**Interfaces:**
- Produces:
  - `output "distribution_domain_name"` → string (e.g. `dxxxx.cloudfront.net`)
  - `output "distribution_id"` → string
- Consumes: `project`, `environment`; `origin_domain_name` (the EC2 EIP public DNS from the compute module).

- [ ] **Step 1: Write `terraform/modules/cdn/variables.tf`**

```hcl
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "origin_domain_name" {
  type        = string
  description = "EC2 public DNS used as the single custom origin."
}
```

- [ ] **Step 2: Write `terraform/modules/cdn/main.tf`**

```hcl
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "this" {
  enabled = true
  comment = "${var.project}-${var.environment} backend"

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "ec2-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "ec2-origin"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_100"
  tags        = { Name = "${var.project}-${var.environment}-cdn" }
}
```

- [ ] **Step 3: Write `terraform/modules/cdn/outputs.tf`**

```hcl
output "distribution_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/cdn && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Format and commit**

```bash
terraform fmt terraform/modules/cdn/
git add terraform/modules/cdn/
git commit -m "feat(cdn): CloudFront reverse proxy with caching disabled, all-viewer forwarding"
```

---

### Task 8: Live root — variables and tfvars example

**Files:**
- Create: `terraform/environments/mirra/variables.tf`
- Create: `terraform/environments/mirra/terraform.tfvars.example`

**Interfaces:**
- Produces: all input variables consumed by `secrets.tf`, `iam.tf`, `main.tf`, `outputs.tf` in later tasks: `project`, `environment`, `region`, `instance_type`, `db_instance_class`, `db_engine_version`, `db_name`, `db_username`, `allowed_origins`, `backend_repo`, `infra_repo`, `app_name`.

- [ ] **Step 1: Write `terraform/environments/mirra/variables.tf`**

```hcl
variable "project" {
  type    = string
  default = "mirra"
}

variable "environment" {
  type    = string
  default = "mirra"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_name" {
  type    = string
  default = "mirra"
}

variable "db_username" {
  type    = string
  default = "mirra"
}

variable "allowed_origins" {
  type        = list(string)
  description = "Vercel production and preview origins for backend CORS and S3 CORS."
}

variable "app_name" {
  type    = string
  default = "Mirra Trading"
}

variable "backend_repo" {
  type        = string
  description = "GitHub owner/repo of mirra-backend, for OIDC sub scoping."
  default     = "ED-Tech1/mirra-backend"
}

variable "infra_repo" {
  type        = string
  description = "GitHub owner/repo of this infra repo, for OIDC sub scoping."
  default     = "ED-Tech1/Mirra-infrastructure"
}
```

- [ ] **Step 2: Write `terraform/environments/mirra/terraform.tfvars.example`**

```hcl
# Copy to terraform.tfvars (gitignored) and fill in real values.
allowed_origins = ["https://mirra-frontend.vercel.app"]
backend_repo    = "ED-Tech1/mirra-backend"
infra_repo      = "ED-Tech1/Mirra-infrastructure"
```

- [ ] **Step 3: Format and commit (validate happens in Task 11 once resources exist)**

```bash
terraform fmt terraform/environments/mirra/
git add terraform/environments/mirra/variables.tf terraform/environments/mirra/terraform.tfvars.example
git commit -m "feat(live): root variables and tfvars example"
```

---

### Task 9: Live root — ECR, generated secrets, Secrets Manager

**Files:**
- Create: `terraform/environments/mirra/secrets.tf`

**Interfaces:**
- Consumes: `var.project`, `var.environment`, `var.db_username`, `var.db_name`, `var.allowed_origins`; `module.database.endpoint` (defined in Task 11's `main.tf` — forward reference, resolved when both files are present).
- Produces (referenced by `iam.tf`, `main.tf`, `outputs.tf`):
  - `aws_ecr_repository.backend.repository_url`
  - `random_password.db.result`
  - `aws_secretsmanager_secret.secret_key.arn`, `.database_url.arn`, `.allowed_origins.arn`

- [ ] **Step 1: Write `terraform/environments/mirra/secrets.tf`**

```hcl
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "random_password" "db" {
  length  = 32
  special = false
}

# SECRET_KEY
resource "aws_secretsmanager_secret" "secret_key" {
  name = "${var.project}/${var.environment}/SECRET_KEY"
}

resource "aws_secretsmanager_secret_version" "secret_key" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = random_password.secret_key.result
}

# DATABASE_URL (depends on the RDS endpoint from module.database)
resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.project}/${var.environment}/DATABASE_URL"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql+psycopg://${var.db_username}:${random_password.db.result}@${module.database.endpoint}/${var.db_name}"
}

# ALLOWED_ORIGINS
resource "aws_secretsmanager_secret" "allowed_origins" {
  name = "${var.project}/${var.environment}/ALLOWED_ORIGINS"
}

resource "aws_secretsmanager_secret_version" "allowed_origins" {
  secret_id     = aws_secretsmanager_secret.allowed_origins.id
  secret_string = join(",", var.allowed_origins)
}
```

Note: `module.database.endpoint` already includes `:5432`, so the URL renders as `...@host:5432/mirra` — do not add a second port.

- [ ] **Step 2: Format and commit**

```bash
terraform fmt terraform/environments/mirra/
git add terraform/environments/mirra/secrets.tf
git commit -m "feat(live): ECR repo and generated SECRET_KEY/DATABASE_URL/ALLOWED_ORIGINS secrets"
```

---

### Task 10: Live root — GitHub OIDC provider and deploy roles

**Files:**
- Create: `terraform/environments/mirra/iam.tf`

**Interfaces:**
- Consumes: `var.backend_repo`, `var.infra_repo`, `var.project`, `var.region`; `aws_ecr_repository.backend.arn`; `aws_secretsmanager_secret.database_url.arn`; `module.compute.instance_id` (forward ref, resolved in Task 11).
- Produces (referenced by `outputs.tf`): `aws_iam_role.backend_deploy.arn`, `aws_iam_role.infra_deploy.arn`.

- [ ] **Step 1: Write `terraform/environments/mirra/iam.tf`**

```hcl
data "aws_caller_identity" "current" {}

# GitHub Actions OIDC provider. Thumbprint is fetched dynamically so it never
# goes stale; AWS also validates GitHub's token signature against its own CA.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ---------- Backend deploy role (assumed by mirra-backend main) ----------
resource "aws_iam_role" "backend_deploy" {
  name = "${var.project}-backend-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.backend_repo}:ref:refs/heads/main" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "backend_deploy" {
  name = "${var.project}-backend-deploy-policy"
  role = aws_iam_role.backend_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.backend.arn
      },
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.database_url.arn
      },
      {
        Sid    = "SsmDeploy"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------- Infra deploy role (assumed by mirra-infra main) ----------
# Broad by necessity: a Terraform apply that manages VPC/EC2/RDS/IAM/CloudFront
# needs wide permissions. Scoped to this repo's main branch via the OIDC sub.
# Tighten to a least-privilege policy before any production hardening pass.
resource "aws_iam_role" "infra_deploy" {
  name = "${var.project}-infra-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.infra_repo}:ref:refs/heads/main" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "infra_deploy_admin" {
  role       = aws_iam_role.infra_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

- [ ] **Step 2: Format and commit**

```bash
terraform fmt terraform/environments/mirra/
git add terraform/environments/mirra/iam.tf
git commit -m "feat(live): GitHub OIDC provider and backend/infra deploy roles"
```

---

### Task 11: Live root — module wiring, outputs, and full validate

**Files:**
- Create: `terraform/environments/mirra/main.tf`
- Create: `terraform/environments/mirra/outputs.tf`

**Interfaces:**
- Consumes: all modules (Tasks 3–7) and `secrets.tf`/`iam.tf` resources (Tasks 9–10).
- Produces: the human-facing outputs, including the Vercel env values.

- [ ] **Step 1: Write `terraform/environments/mirra/main.tf`**

```hcl
module "network" {
  source      = "../../modules/network"
  project     = var.project
  environment = var.environment
}

module "storage" {
  source          = "../../modules/storage"
  project         = var.project
  environment     = var.environment
  bucket_suffix   = data.aws_caller_identity.current.account_id
  allowed_origins = var.allowed_origins
}

module "compute" {
  source             = "../../modules/compute"
  project            = var.project
  environment        = var.environment
  region             = var.region
  vpc_id             = module.network.vpc_id
  public_subnet_id   = module.network.public_subnet_ids[0]
  instance_type      = var.instance_type
  ecr_repository_url = aws_ecr_repository.backend.repository_url
  storage_bucket_arn = module.storage.bucket_arn
  secret_arns = {
    secret_key      = aws_secretsmanager_secret.secret_key.arn
    database_url    = aws_secretsmanager_secret.database_url.arn
    allowed_origins = aws_secretsmanager_secret.allowed_origins.arn
  }
}

module "database" {
  source                = "../../modules/database"
  project               = var.project
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.compute.security_group_id
  instance_class        = var.db_instance_class
  engine_version        = var.db_engine_version
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = random_password.db.result
}

module "cdn" {
  source             = "../../modules/cdn"
  project            = var.project
  environment        = var.environment
  origin_domain_name = module.compute.instance_public_dns
}
```

Dependency note: `compute` references only secret ARNs (not the DB endpoint), so it can be created before `database`. `database` depends on `compute` for the app security group. `secrets.tf`'s `database_url` version depends on `module.database.endpoint`. This ordering is acyclic — Terraform resolves it automatically.

- [ ] **Step 2: Write `terraform/environments/mirra/outputs.tf`**

```hcl
output "cloudfront_url" {
  description = "Backend HTTPS base URL — set as the frontend's NEXT_PUBLIC_API_URL."
  value       = "https://${module.cdn.distribution_domain_name}"
}

output "cloudfront_distribution_id" {
  value = module.cdn.distribution_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ec2_instance_id" {
  value = module.compute.instance_id
}

output "rds_endpoint" {
  value     = module.database.endpoint
  sensitive = true
}

output "storage_bucket" {
  value = module.storage.bucket_id
}

output "backend_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN secret in mirra-backend."
  value       = aws_iam_role.backend_deploy.arn
}

output "infra_deploy_role_arn" {
  description = "Set as the TF_INFRA_ROLE_ARN secret in this repo."
  value       = aws_iam_role.infra_deploy.arn
}

output "vercel_env" {
  description = "Environment variables to set on the Vercel project."
  value = {
    NEXT_PUBLIC_API_URL  = "https://${module.cdn.distribution_domain_name}"
    NEXT_PUBLIC_APP_NAME = var.app_name
  }
}
```

- [ ] **Step 3: Validate the entire live root (integration check)**

Run: `cd terraform/environments/mirra && terraform init -backend=false && terraform validate && cd -`
Expected: `Success! The configuration is valid.`
If it reports an undeclared reference or type mismatch, fix the offending file before continuing — this is the integration gate for Tasks 3–11.

- [ ] **Step 4: Format and commit**

```bash
terraform fmt -recursive terraform/
git add terraform/environments/mirra/main.tf terraform/environments/mirra/outputs.tf
git commit -m "feat(live): wire modules together with outputs incl. Vercel env"
```

---

### Task 12: Infra CI/CD — terraform plan (PR) / apply (push to main)

**Files:**
- Create: `.github/workflows/terraform.yml`

**Interfaces:**
- Consumes: repo secret `TF_INFRA_ROLE_ARN` (the infra deploy role ARN from Task 11 output) and a committed `terraform/environments/mirra/backend.hcl` (operator creates from the `.example`).

- [ ] **Step 1: Write `.github/workflows/terraform.yml`**

```yaml
name: terraform

on:
  push:
    branches: [main]
    paths:
      - "terraform/**"
      - ".github/workflows/terraform.yml"
  pull_request:
    paths:
      - "terraform/**"
      - ".github/workflows/terraform.yml"

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform/environments/mirra
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.8

      - name: Format check
        run: terraform fmt -check -recursive
        working-directory: terraform

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.TF_INFRA_ROLE_ARN }}
          aws-region: eu-north-1

      - name: Init
        run: terraform init -backend-config=backend.hcl

      - name: Validate
        run: terraform validate

      - name: Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -input=false

      - name: Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -input=false -auto-approve
```

- [ ] **Step 2: Lint the workflow (if `actionlint` is available)**

Run: `actionlint .github/workflows/terraform.yml || echo "actionlint not installed — skip"`
Expected: no errors (or the skip message).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/terraform.yml
git commit -m "ci: terraform plan on PR, apply on push to main via OIDC"
```

---

### Task 13: Reusable backend deploy workflow (lives in infra repo)

**Files:**
- Create: `.github/workflows/reusable-backend-deploy.yml`

**Interfaces:**
- Called cross-repo by `mirra-backend`. Input secret `deploy-role-arn`. Builds/pushes the image, migrates over an SSM tunnel, and restarts the service.
- Note: callable reusable workflows must sit directly in `.github/workflows/` (not a subdirectory) — that matches where this repo's other reusable workflows already live.

- [ ] **Step 1: Write `.github/workflows/reusable-backend-deploy.yml`**

```yaml
name: reusable-backend-deploy

on:
  workflow_call:
    inputs:
      aws-region:
        type: string
        default: eu-north-1
      ecr-repository:
        type: string
        default: mirra-backend
      instance-name-tag:
        type: string
        default: mirra-mirra-api
      rds-secret-id:
        type: string
        default: mirra/mirra/DATABASE_URL
    secrets:
      deploy-role-arn:
        required: true

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.deploy-role-arn }}
          aws-region: ${{ inputs.aws-region }}

      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr

      - name: Build and push image
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          REPO: ${{ inputs.ecr-repository }}
          SHA: ${{ github.sha }}
        run: |
          docker build -t "$REGISTRY/$REPO:$SHA" -t "$REGISTRY/$REPO:latest" .
          docker push "$REGISTRY/$REPO:$SHA"
          docker push "$REGISTRY/$REPO:latest"

      - name: Resolve instance id
        id: ec2
        run: |
          ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${{ inputs.instance-name-tag }}" \
                      "Name=instance-state-name,Values=running" \
            --query "Reservations[0].Instances[0].InstanceId" --output text)
          echo "id=$ID" >> "$GITHUB_OUTPUT"

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - uses: astral-sh/setup-uv@v5

      - name: Install Session Manager plugin
        run: |
          curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o smp.deb
          sudo dpkg -i smp.deb

      - name: Run migrations over SSM tunnel
        env:
          INSTANCE_ID: ${{ steps.ec2.outputs.id }}
          RDS_SECRET: ${{ inputs.rds-secret-id }}
        run: |
          DB_URL=$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET" --query SecretString --output text)
          HOSTPORT=$(echo "$DB_URL" | sed -E 's#.*@([^/]+)/.*#\1#')
          RDS_HOST="${HOSTPORT%%:*}"
          RDS_PORT="${HOSTPORT##*:}"

          aws ssm start-session \
            --target "$INSTANCE_ID" \
            --document-name AWS-StartPortForwardingSessionToRemoteHost \
            --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"$RDS_PORT\"],\"localPortNumber\":[\"5432\"]}" &
          SSM_PID=$!
          sleep 10

          LOCAL_DB_URL=$(echo "$DB_URL" | sed -E "s#@[^/]+/#@localhost:5432/#")
          DATABASE_URL="$LOCAL_DB_URL" uv run alembic upgrade head

          kill "$SSM_PID" 2>/dev/null || true

      - name: Restart backend service
        env:
          INSTANCE_ID: ${{ steps.ec2.outputs.id }}
        run: |
          CMD=$(aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["systemctl restart mirra-backend.service"]' \
            --query "Command.CommandId" --output text)
          aws ssm wait command-executed --command-id "$CMD" --instance-id "$INSTANCE_ID" || true
          aws ssm get-command-invocation --command-id "$CMD" --instance-id "$INSTANCE_ID"
```

Note: `uv run alembic upgrade head` runs on the runner against `localhost:5432`, which the SSM port-forward maps to RDS. `uv run` installs deps from the checked-out `mirra-backend` `uv.lock` on demand. The migration executes on the runner (as chosen), while RDS stays private.

- [ ] **Step 2: Lint the workflow (if `actionlint` is available)**

Run: `actionlint .github/workflows/reusable-backend-deploy.yml || echo "actionlint not installed — skip"`
Expected: no errors (or the skip message).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/reusable-backend-deploy.yml
git commit -m "ci: reusable backend deploy (build, push, migrate over SSM tunnel, restart)"
```

---

### Task 14: Backend repo — Dockerfile (NEW FILE)

**Files:**
- Create: `/Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend/Dockerfile`

**Interfaces:**
- Produces a runnable image whose `CMD` starts uvicorn on `:8000`, consumed by `deploy.sh` on the instance and by the reusable deploy workflow.
- CONSTRAINT: new file only. Do not touch any existing backend file.

- [ ] **Step 1: Write the `Dockerfile`**

```dockerfile
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# uv binary from the official distroless image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Install dependencies first (layer cache) using only the lockfiles
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# App source
COPY . .
RUN uv sync --frozen --no-dev

EXPOSE 8000
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Build to verify it produces a working image**

Run:
```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend
docker build -t mirra-backend:plan-check .
```
Expected: build completes; final line `naming to docker.io/library/mirra-backend:plan-check`. (Requires Docker and network access. If Docker is unavailable in this environment, note it and defer the build to CI, where it runs as the first deploy step.)

- [ ] **Step 3: Smoke-test the image boots (boot-guard expects prod env; use a dummy non-default config)**

Run:
```bash
docker run --rm -e ENVIRONMENT=development -e DATABASE_URL=postgresql+psycopg://x:y@localhost:5432/z \
  -p 8001:8000 -d --name mirra-smoke mirra-backend:plan-check
sleep 5
curl -fsS http://localhost:8001/health
docker rm -f mirra-smoke
```
Expected: `{"status":"ok","environment":"development"}` (uses `development` to avoid the production boot-guard during a local smoke test; production config is supplied at real deploy time via Secrets Manager).

- [ ] **Step 4: Commit (in the backend repo)**

```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend
git add Dockerfile
git commit -m "feat: add Dockerfile for containerized deploy"
```

---

### Task 15: Backend repo — deploy.yml caller (NEW FILE)

**Files:**
- Create: `/Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend/.github/workflows/deploy.yml`

**Interfaces:**
- Consumes: backend repo secret `AWS_DEPLOY_ROLE_ARN` (the `backend_deploy_role_arn` output from Task 11). Calls the reusable workflow in the infra repo.
- CONSTRAINT: new file only. The existing `ci.yml` is NOT modified.

- [ ] **Step 1: Write the caller workflow**

```yaml
name: deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    uses: ED-Tech1/Mirra-infrastructure/.github/workflows/reusable-backend-deploy.yml@main
    secrets:
      deploy-role-arn: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
```

- [ ] **Step 2: Lint (if `actionlint` is available)**

Run: `actionlint .github/workflows/deploy.yml || echo "actionlint not installed — skip"`
Expected: no errors (or skip message).

- [ ] **Step 3: Commit (in the backend repo)**

```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend
git add .github/workflows/deploy.yml
git commit -m "ci: auto-deploy to AWS on push to main via infra reusable workflow"
```

---

### Task 16: Operator runbook + push infra repo

**Files:**
- Create: `docs/runbooks/aws-deploy.md`
- Modify: `README.md` (append an "AWS deployment" pointer — this repo's own README, allowed)

**Interfaces:**
- Produces the manual bootstrap + first-apply procedure and the secret-wiring checklist that CI depends on.

- [ ] **Step 1: Write `docs/runbooks/aws-deploy.md`**

````markdown
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
terraform output backend_deploy_role_arn   # -> mirra-backend repo secret AWS_DEPLOY_ROLE_ARN
terraform output infra_deploy_role_arn      # -> this repo secret TF_INFRA_ROLE_ARN
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

Push to `mirra-backend` `main` (or re-run its `deploy` workflow). It builds the
image, runs `alembic upgrade head` over the SSM tunnel, and starts the container.
Verify: `curl https://<dist>.cloudfront.net/health`.
````

- [ ] **Step 2: Append the pointer to `README.md`**

Add this section to the end of `README.md`:

```markdown
## AWS deployment

This repo deploys the backend to AWS (eu-north-1) via Terraform. See
`docs/runbooks/aws-deploy.md` for the one-time bootstrap and first apply, and
`docs/superpowers/specs/2026-06-21-aws-backend-deployment-design.md` for the design.
The frontend is deployed separately on Vercel.
```

- [ ] **Step 3: Commit and push the infra repo**

```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-infra
git add docs/runbooks/aws-deploy.md README.md
git commit -m "docs: AWS deployment runbook and README pointer"
git push -u origin main
```
Expected: push succeeds to `github.com/ED-Tech1/Mirra-infrastructure`. If auth is rejected, STOP and hand the push back to the operator (do not attempt to inject credentials).

- [ ] **Step 4: Push the backend repo's new files**

```bash
cd /Users/chinecheremkalu/IdeaProjects/mirra-platform-scaffold/mirra-backend
git push
```
Expected: the `Dockerfile` and `deploy.yml` commits push to the backend remote. If auth is rejected, STOP and hand back to the operator.

---

## Self-Review

**1. Spec coverage:**
- §2 topology (CloudFront→EC2→RDS, S3) → Tasks 3,5,6,7,4. ✓
- §3 Terraform layout (single env, prune stubs, versions/backend) → Tasks 1,8–11. ✓
- §3 state bootstrap → Task 2. ✓
- §4 secrets + user_data/deploy.sh + boot-guard → Tasks 9,6. ✓
- §5 IAM (instance role, two OIDC roles) → Tasks 6,10. ✓
- §6 storage bucket + CORS → Task 4. ✓
- §7.1 backend CI (Dockerfile, caller, build/migrate/deploy) → Tasks 14,15,13. ✓
- §7.2 infra CI (plan/apply) → Task 12. ✓
- §8 Vercel outputs → Task 11. ✓
- §9 git init + remote + push → Tasks 1,16. ✓
- Migrations-from-Actions-over-SSM-tunnel → Task 13. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N" — every code block is complete. The only `<...>` tokens are in example/config files the operator fills (`backend.hcl.example`, account id), which is correct.

**3. Type/name consistency:**
- Module outputs match consumers: `network.{vpc_id,public_subnet_ids,private_subnet_ids}`, `compute.{instance_id,instance_public_dns,security_group_id}`, `database.endpoint`, `storage.bucket_arn`, `cdn.distribution_domain_name` — all referenced exactly as produced in Task 11. ✓
- `secret_arns` map keys (`secret_key`/`database_url`/`allowed_origins`) consistent between Task 6 (consumer) and Task 11 (producer). ✓
- EC2 `Name` tag `mirra-mirra-api` matches the deploy workflow's `instance-name-tag` default. ✓
- Secret names `mirra/mirra/DATABASE_URL` match the workflow's `rds-secret-id` default. ✓
- `backend_deploy_role_arn` / `infra_deploy_role_arn` outputs map to the `AWS_DEPLOY_ROLE_ARN` / `TF_INFRA_ROLE_ARN` secrets used in Tasks 15/12. ✓
