
variable "config" {
  type = object({
    environment = string
    region      = string
    profile     = string
    projectName = string
  })
}

module "vpc" {  
   source = "./vpc"   
   config = {    
   environment = var.environment    
   profile     = var.profile    
   region      = var.region    
   projectName = var.projectName  
  }
}

module "ec2_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name   = "ec2_sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = local.service_port #80
      to_port     = local.service_port #80
      protocol    = "tcp"
      description = "http port"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = local.ssh_port #22
      to_port     = local.ssh_port #22
      protocol    = "tcp"
      description = "ssh port"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port = 0
      to_port   = 0
      protocol  = "-1"
    cidr_blocks = "0.0.0.0/0" }
  ]
}

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}


resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_launch_configuration" "ecs_config_launch_config_spot" {
  name_prefix                 = "${var.cluster_name}_ecs_cluster_spot"
  image_id                    = data.aws_ami.aws_optimized_ecs.id
  instance_type               = var.instance_type_spot
  spot_price                  = var.spot_bid_price
  associate_public_ip_address = true
  lifecycle {
    create_before_destroy = true
  }
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
EOF

  security_groups = [module.ec2_sg.security_group_id]

  key_name             = aws_key_pair.ecs.key_name
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.arn
}

data "aws_ami" "aws_optimized_ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami*amazon-ecs-optimized"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"] # AWS
}

resource "aws_autoscaling_group" "ecs_cluster_spot" {
  name_prefix = "${var.cluster_name}_asg_spot_"
  termination_policies = [
     "OldestInstance" 
  ]
  default_cooldown          = 30
  health_check_grace_period = 30
  max_size                  = var.max_spot
  min_size                  = var.min_spot
  desired_capacity          = var.min_spot

  launch_configuration      = aws_launch_configuration.ecs_config_launch_config_spot.name

  lifecycle {
    create_before_destroy = true
  }
  vpc_zone_identifier = data.terraform_remote_state.vpc.outputs.vpc_id

  tags = [
    {
      key                 = "Name"
      value               = var.cluster_name,

      propagate_at_launch = true
    }
  ]
}

