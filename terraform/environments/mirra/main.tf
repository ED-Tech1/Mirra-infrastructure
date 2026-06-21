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
