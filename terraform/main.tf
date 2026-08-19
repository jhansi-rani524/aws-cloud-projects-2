terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "us-east-2"
}
resource "aws_vpc" "project2_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "project2-vpc"
  }
}
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.project2_vpc.id
  cidr_block               = "10.1.1.0/24"
  availability_zone        = "us-east-2a"
  map_public_ip_on_launch  = true

  tags = {
    Name = "project2-public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.project2_vpc.id
  cidr_block               = "10.1.2.0/24"
  availability_zone        = "us-east-2b"
  map_public_ip_on_launch  = true

  tags = {
    Name = "project2-public-subnet-2"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.project2_vpc.id
  cidr_block         = "10.1.3.0/24"
  availability_zone  = "us-east-2a"

  tags = {
    Name = "project2-private-subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.project2_vpc.id
  cidr_block         = "10.1.4.0/24"
  availability_zone  = "us-east-2b"

  tags = {
    Name = "project2-private-subnet-2"
  }
}
resource "aws_internet_gateway" "project2_igw" {
  vpc_id = aws_vpc.project2_vpc.id

  tags = {
    Name = "project2-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.project2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.project2_igw.id
  }

  tags = {
    Name = "project2-public-rt"
  }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}
# 1. ALB Security Group — allows HTTP from the whole internet
resource "aws_security_group" "alb_sg" {
  name        = "project2-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.project2_vpc.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project2-alb-sg"
  }
}

# 2. EC2 Security Group — allows HTTP only from the ALB
resource "aws_security_group" "ec2_sg" {
  name        = "project2-ec2-sg"
  description = "Allow HTTP only from ALB"
  vpc_id      = aws_vpc.project2_vpc.id

  ingress {
    description     = "HTTP from ALB only"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project2-ec2-sg"
  }
}

# 3. RDS Security Group — allows MySQL only from EC2
resource "aws_security_group" "rds_sg" {
  name        = "project2-rds-sg"
  description = "Allow MySQL only from EC2"
  vpc_id      = aws_vpc.project2_vpc.id

  ingress {
    description     = "MySQL from EC2 only"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project2-rds-sg"
  }
}
# 1. The IAM role EC2 instances will assume
resource "aws_iam_role" "ec2_role" {
  name = "project2-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "project2-ec2-role"
  }
}

# 2. Attach AWS's managed SSM policy to that role
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3. Instance profile — the actual object EC2 launch configs attach to
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "project2-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
# Look up the latest Amazon Linux 2023 AMI automatically
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "project2_lt" {
  name_prefix   = "project2-launch-template"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "Server - $(hostname)" > /usr/share/nginx/html/index.html
  EOF
  )

  tags = {
    Name = "project2-launch-template"
  }
}

resource "aws_autoscaling_group" "project2_asg" {
  name                = "project2-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns = [aws_lb_target_group.project2_tg.arn]

  launch_template {
    id      = aws_launch_template.project2_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "project2-asg-instance"
    propagate_at_launch = true
  }
}
resource "aws_lb" "project2_alb" {
  name               = "project2-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "project2-alb"
  }
}

resource "aws_lb_target_group" "project2_tg" {
  name     = "project2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.project2_vpc.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "project2-tg"
  }
}

resource "aws_lb_listener" "project2_listener" {
  load_balancer_arn = aws_lb.project2_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.project2_tg.arn
  }
}

resource "aws_db_subnet_group" "project2_rds_subnet_group" {
  name       = "project2-rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "project2-rds-subnet-group"
  }
}

resource "aws_db_instance" "project2_db" {
  identifier             = "project2-db"
  engine                 = "mysql"
  engine_version         = "8.4"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = "project2db"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.project2_rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true

  tags = {
    Name = "project2-db"
  }
}