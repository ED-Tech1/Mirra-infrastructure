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
