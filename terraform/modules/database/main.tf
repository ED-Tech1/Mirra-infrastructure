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
