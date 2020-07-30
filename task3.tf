provider "aws" {
	region = "ap-south-1"
	profile = "mohit"
}

#ssh key generation
resource "tls_private_key" "keygen" {
  algorithm   = "RSA"  
}


#Creating key pair in aws
resource "aws_key_pair" "newKey" {
depends_on=[
	tls_private_key.keygen
]
  key_name   = "webkey1"
  public_key = tls_private_key.keygen.public_key_openssh
}


#Saving private key in local file
resource "local_file" "privatekey" {
depends_on=[
	aws_key_pair.newKey
]
    content     = tls_private_key.keygen.private_key_pem
    filename = "C:/Users/Dell/Downloads/webkey1.pem"
}


#VPC
resource "aws_vpc" "app-vpc" {
depends_on=[
	local_file.privatekey
]
  cidr_block       = "172.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
    Name = "main"
  }
}



#public subnet
resource "aws_subnet" "sn-pub-1a" {
depends_on=[
	aws_vpc.app-vpc
]
  vpc_id     = "${aws_vpc.app-vpc.id}"
  cidr_block = "172.168.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"
  tags = {
    Name = "Wordpress"
  }
}


#Private subnet
resource "aws_subnet" "sn-pri-1b" {
depends_on=[
	aws_vpc.app-vpc
]
  vpc_id     = "${aws_vpc.app-vpc.id}"
  cidr_block = "172.168.1.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "MySql"
  }
}


# Internate Gateway
resource "aws_internet_gateway" "igw" {
depends_on=[
	aws_subnet.sn-pub-1a
]
  vpc_id = "${aws_vpc.app-vpc.id}"

  tags = {
    Name = "main"
  }
}


# Creating route table
resource "aws_route_table" "wp-route" {
depends_on=[
	aws_internet_gateway.igw
]
  vpc_id = "${aws_vpc.app-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags = {
    Name = "wp-route"
  }
}


#Associating Route Table
resource "aws_route_table_association" "a" {
depends_on=[
	aws_route_table.wp-route
]
  subnet_id      = "${aws_subnet.sn-pub-1a.id}"
  route_table_id = "${aws_route_table.wp-route.id}"
}



#Security rule for WP-instance
resource "aws_security_group" "wp-sg" {
depends_on=[
	aws_vpc.app-vpc
]
  name        = "wp-sg"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "${aws_vpc.app-vpc.id}"

  ingress {
    description = "For http users"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "For http users"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "For ssh login if needed"
    from_port   = 22
    to_port     = 22
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
    Name = "wp-sg"
  }
}



# Security group for mysql instance
resource "aws_security_group" "mysql-sg" {
depends_on=[
	aws_security_group.wp-sg
]
  name        = "mysql-sg"
  description = "Allows 3306 port."
  vpc_id      = "${aws_vpc.app-vpc.id}"

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    cidr_blocks = ["172.168.0.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.168.0.0/24"]
  }

  tags = {
    Name = "allow mysql user"
  }
}


# MySql Instance creation
resource "aws_instance" "mysql-ins" {
  ami           = "ami-0525596cfb1f1d80d"
  instance_type = "t2.micro"
  key_name      = "webkey1"
  availability_zone = "ap-south-1b"
  subnet_id     = "${aws_subnet.sn-pri-1b.id}"
  private_ip = "172.168.1.136"
  security_groups = [ "${aws_security_group.mysql-sg.id}" ]
  root_block_device {
	volume_size = 10
  }
  tags = {
    Name = "MySQL"
  }
}


# Wordpress Instance
resource "aws_instance" "wp-ins" {
depends_on=[
	aws_instance.mysql-ins
]
  ami           = "ami-0d495011f875f3db3"
  instance_type = "t2.micro"
  key_name      = "webkey1"
  availability_zone = "ap-south-1a"
  subnet_id     = "${aws_subnet.sn-pub-1a.id}"
  security_groups = [ "${aws_security_group.wp-sg.id}" ]
  root_block_device {
	volume_size = 10
  }
  tags = {
    Name = "Wordpress"
  }
}

