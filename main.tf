provider "aws" {
    region = var.region
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"
  tags = {
    name = "AvaliabiltyVPC"
  }
}

resource "aws_internet_gateway" "ava_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "AvaliabiltyIGW"
  }
}

resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "eu-west-1a"
  tags = {
    Name = "AvaliabilityPublicSubnet1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "eu-west-1b"
  tags = {
    Name = "AvaliabilityPublicSubnet2"
  }
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "eu-west-1a"

  tags = {
    Name = "AvaliabilityPrivateSubnet1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "eu-west-1b"

  tags = {
    Name = "AvaliabilityPrivateSubnet2"
  }
}

resource "aws_route_table" "public_subnet_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ava_igw.id
  }

  tags = {
    "Name" = "AvaliabiltyPublicRT"
  }
}

resource "aws_route_table" "private_subnet_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ava_igw.id
  }

  tags = {
    "Name" = "AvaliailityPrivateRT"
  }
}

resource "aws_route_table_association" "subnet1_rt_public" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public_subnet_rt.id
}

resource "aws_route_table_association" "subnet2_rt_public" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public_subnet_rt.id
}


resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_subnet_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ava_igw.id
}

resource "aws_route_table_association" "subnet1_rt_private" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private_subnet_rt.id
}

resource "aws_route_table_association" "subnet2_rt_private" {
  subnet_id      = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.private_subnet_rt.id
}

resource "aws_eip" "nat_eip" {}

resource "aws_nat_gateway" "nat_gateway" {
    allocation_id = aws_eip.nat_eip.id
    subnet_id = aws_subnet.private-subnet-1.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_subnet_rt.id
  destination_cidr_block = "0.0.0.0/24"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

resource "aws_security_group" "elb_sg" {
  name        = "elb-security-group"
  description = "Security group for ELBs"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "internal_elb_sg" {
  name        = "internal-elb-security-group"
  description = "Security group for internal ELB"
  vpc_id      = aws_vpc.my_vpc.id
}

resource "aws_lb" "internet_facing_elb" {
  name               = "internet-facing-elb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id] 

  enable_deletion_protection = false

  enable_http2 = true 

  enable_cross_zone_load_balancing = true 

  security_groups = [aws_security_group.elb_sg.id]
}

resource "aws_lb" "internal_elb" {
  name               = "internalelb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id] 

  enable_deletion_protection = false

  enable_http2 = true 

  enable_cross_zone_load_balancing = true 

  security_groups = [aws_security_group.internal_elb_sg.id]
}

resource "aws_lb_target_group" "internet_facing_target_group" {
  name     = "internet-facing-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "internal_target_group" {
  name     = "internal-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path                = "/internal-health-check"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_autoscaling_group" "ava_asg" {
  name_prefix                   = "ava-asg-"
  launch_template {
    id                          = aws_launch_template.ava_lt.id
    version                     = "$Latest"
  }
  vpc_zone_identifier           = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id, aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
  min_size                      = 2
  max_size                      = 5
  desired_capacity              = 2
  target_group_arns             = [aws_lb_target_group.internal_target_group.arn]
  termination_policies          = ["OldestLaunchConfiguration"]
}

resource "aws_launch_template" "ava_lt" {
  name                           = "ava-launch-template"
  description                    = "Avaliability Launch Template"
  block_device_mappings {
    device_name                  = "/dev/xvda"
    ebs {
      volume_size                = 20
      delete_on_termination      = true
      volume_type                = "gp2"
    }
  }
  
  instance_type = "t2.micro"
  key_name = "terraform_keypair"
  
  image_id = "ami-0dab0800aa38826f2"
  tag_specifications {
    resource_type                = "instance"
    tags = {
      Name                       = "ava-instance"
    }
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-security-group"
  description = "Security group for Bastion Host"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP address or IP range
  }
}

resource "aws_instance" "bastion_host" {
  ami                    = "ami-0dab0800aa38826f2" 
  instance_type          = "t2.micro"    
  key_name               = "terraform_keypair"
  subnet_id              = aws_subnet.public-subnet-1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "Bastion Host"
  }
}






