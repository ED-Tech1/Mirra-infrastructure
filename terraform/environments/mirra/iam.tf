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
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.backend_repo}:ref:refs/heads/main"
        }
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
          "ec2:DescribeInstances",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
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
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.infra_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "infra_deploy_admin" {
  role       = aws_iam_role.infra_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
