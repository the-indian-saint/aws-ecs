# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.config.projectName}-${var.config.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.config.region}a", "${var.config.region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.2.0/24", "10.0.4.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Default security group - ingress/egress rules cleared to deny all
  manage_default_security_group  = false
  default_security_group_ingress = [{}]
  default_security_group_egress  = [{}]
}
