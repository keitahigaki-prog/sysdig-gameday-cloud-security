## 5チーム共通のEKSクラスタTerraformテンプレート。
## team_name / account_id / participant_role_name をteamごとに変えて、各チームのAWSアカウント(プロファイル)で
## 個別にterraform init/applyする。provision_eks_all_teams.shがこれを自動でやる。

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  default = "ap-southeast-2" # Sydney
}

variable "team_name" {
  description = "例: team-a"
  type        = string
}

variable "account_id" {
  description = "このチームのAWSアカウントID"
  type        = string
}

variable "participant_role_name" {
  description = "IAM Identity CenterのGameDayParticipantAccess許可セットのロール名(例: AWSReservedSSO_GameDayParticipantAccess_xxxxxxxxxxxxxxxx)。各アカウントでaws iam list-roles --profile gameday-<team> | grep GameDayParticipantAccess で確認する。"
  type        = string
}

provider "aws" {
  region = var.region
}

data "aws_iam_role" "participant" {
  name = var.participant_role_name
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "gameday-${var.team_name}"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    gameday = var.team_name
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "gameday-${var.team_name}"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size       = 2
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3.medium"]
    }
  }

  # 参加者にクラスタ管理者権限を渡すため、GameDay用のロールをクラスタ管理者として追加
  access_entries = {
    gameday_admin = {
      principal_arn = data.aws_iam_role.participant.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    gameday = var.team_name
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name gameday-${var.team_name} --alias ${var.team_name}"
}
