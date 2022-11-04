provider "aws" {
  region = "ca-central-1"
}

# DATA BLOCKS
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
   filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "userdata_sh" {
  template = file("./scripts/userdata.sh")
  vars = {
    vpc_id = aws_vpc.test_vpc.id
  }
}

# NETWORK BLOCKS
resource "aws_vpc" "test_vpc" {
  cidr_block       = var.aws_vpc_cidr_block
  enable_dns_support = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name = "test_vpc"
  }
}

resource "aws_subnet" "test_subnet" {
  count = length(var.availability_zone)
  vpc_id = aws_vpc.test_vpc.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = element(var.availability_zone, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = {
    Name = "test_subnet_public"
  }
}

resource "aws_internet_gateway" "test_igw" {
  vpc_id = aws_vpc.test_vpc.id

  tags = {
    Name = "test_igw"
  }
}

resource "aws_route_table" "test_rt" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block = var.aws_route_table_route_cidr
    gateway_id = aws_internet_gateway.test_igw.id
  }
  
  tags = {
    Name = "test_rt"
  }
}

resource "aws_route_table_association" "test_rt_assoc" {
  count = length(var.availability_zone)
  route_table_id = aws_route_table.test_rt.id
  subnet_id = aws_subnet.test_subnet[count.index].id
}

# SERVER BLOCKS
resource "aws_instance" "test_server" {
  count = length(var.availability_zone)
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.test_sg.id]
  subnet_id = aws_subnet.test_subnet[count.index].id
  key_name = aws_key_pair.test_key.key_name
  user_data = data.template_file.userdata_sh.rendered

  tags = {
    Name = "test_server-${count.index + 1}"
  }
}

resource "aws_security_group" "test_sg" {
  name        = var.aws_security_group_name
  description = var.aws_security_group_description
  vpc_id      = aws_vpc.test_vpc.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = var.protocol_tcp
    cidr_blocks      = var.security_group_cidr_blocks
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = var.protocol_tcp
    cidr_blocks      = var.security_group_cidr_blocks
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = var.security_group_cidr_blocks
  }

  tags = {
    Name = "test-sg"
  }
}

resource "aws_key_pair" "test_key" {
  key_name   = var.aws_key_pair_name
  public_key = var.aws_key_pair_public
}

# APPLICATION LOAD BALANCER
resource "aws_alb" "test-alb" {
  name               = "test-alb"
  security_groups    = [aws_security_group.test_sg.id]
  subnets            = [for subnet in aws_subnet.test_subnet : subnet.id]

  tags = {
    Name = "test-ALB"
  }
}

resource "aws_alb_listener" "listener_http" {
  load_balancer_arn = aws_alb.test-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.target_gr.arn
    type             = "forward"
  }
}

resource "aws_alb_target_group" "target_gr" {
  name     = "test-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.test_vpc.id
}

resource "aws_alb_target_group_attachment" "target_gr_attach" {
  count = length(aws_instance.test_server)
  target_group_arn = aws_alb_target_group.target_gr.arn
  target_id = aws_instance.test_server[count.index].id
}