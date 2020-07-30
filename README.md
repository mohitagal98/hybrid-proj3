# Hosting Wordpress considering Database security on Cloud
In my last article, we have seen how to setup the Wordpress and MySql in two different instances. But there was a problem with previous setup that it was highly vulnerable or hackers can easily attack on our database server.

So in this article I will setup the same infrastructure using terraform but will use the concepts of VPC, subnets to secure the database server.

Please go through my earlier articles for better understanding:  [Article-1](https://www.linkedin.com/pulse/setting-up-wordpress-mysql-two-different-ec2-mohit-agarwal/) and [Article-2](https://www.linkedin.com/pulse/cloud-automation-terraform-mohit-agarwal/).
## Purpose:
We have to create a web portal for our company with all the security as much as possible.

### Steps:

1) Write a Infrastructure as code using terraform, which automatically create a VPC.

2) In that VPC we have to create 2 subnets:

  a) public subnet [ Accessible for Public World! ] for Wordpress

  b) private subnet [ Restricted for Public World! ] for MySQL

3) Create a public facing internet gateway for connecting our VPC/Network to the internet world and attach this gateway to our VPC.

4) Create a routing table for Internet gateway so that instance can connect to outside world, update and associate it with public subnet.

5) Launch an EC2 instance which has Wordpress setup already having the security group allowing port 80 and port 443 so that our client can connect to our wordpress site.

6) Launch an EC2 instance which has MySQL setup already with security group allowing port 3306 in private subnet so that our wordpress vm can connect with the same.

## Implementation
In my previous article whatever we had done, I have created an AMI from both the instances, till the setup part, in which MySQL and Wordpress is already setup. So I just need to implement some security using concepts of VPC, public and private subnet, etc.

In my earlier articles we have already seen how to generate key and use it. So let's start here by creating VPC.
### Create VPC:
```
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
```
Here, aws_vpc resource will create the VPC and I have assigned cidr_block:"172.168.0.0/16" which can also be seen as a network name of this particular VPC.

### Create Public Subnet:
```
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
```
Create one subnet in the VPC, and will make it publicly available for Wordpress. (Note: It is not publicly accessible till now.)

### Private Subnet:
```
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
```
Create one more subnet in VPC where we will put MySql instance. We will not assign any internet connectivity to it and hence nobody can connect from public world and eventually ensuring security.

### Create an Internet Gateway:
```
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
```
An internet gateway is a horizontally scaled, redundant, and highly available VPC component that allows communication between your VPC and the internet.

### Create Route Table:
```
# Creating Route Table

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
```
This will create a route table which will set the above created Internet Gateway as a target for internet-routable traffic.

### Associate Route Table with Subnet:
```
resource "aws_route_table_association" "a" {
depends_on=[
	aws_route_table.wp-route
]
  subnet_id      = "${aws_subnet.sn-pub-1a.id}"
  route_table_id = "${aws_route_table.wp-route.id}"
}
```
This will associate route table with the subnet where we will launch Wordpress Instance for two purposes:

1. Instances is this subnet can access Internet,
2. And to perform network address translation (NAT) for instances that have been assigned public IPv4 addresses.
### Security group for Wordpress:
```
#Security rule with some ingress rule

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
```
This will create scurity group for Wordpress instance allowing only 80/443 port for web access and 22 port for ssh login to manage instance.

### Security group for MySQL:
```
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
```
This will create security group for MySQL instance allowing only instances in public subnet to access 3306 port as MySQL server works on this port.

### Create MySQL Instance:
```
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
```
This will create an instance using MySQL AMI(which is in my private repository) and will put that instance in Private subnet. Moreover fixing Private_IP because I have configured my Wordpress using this IP as database host.

### Create Wordpress Instance:
```
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
```
The above part will create the Wordpress Instance and will put it in Public Subnet.

To see complete code, click [here](https://github.com/mohitagal98/hybrid-proj3/blob/master/task3.tf).

Now, complete setup is done. And again we are left with our two magic commands i.e.
```
terraform init
terraform apply -auto-approve
```
Everything is done, to verify use GUI to see if all resources are working.
VPC:
![01](https://raw.githubusercontent.com/mohitagal98/hybrid-proj3/master/Images/vpc.JPG)

SUBNETS:
![02](https://raw.githubusercontent.com/mohitagal98/hybrid-proj3/master/Images/subnet.JPG)

Internet Gateway:
![03](https://raw.githubusercontent.com/mohitagal98/hybrid-proj3/master/Images/igw.JPG)

Instances:
![04](https://raw.githubusercontent.com/mohitagal98/hybrid-proj3/master/Images/instances.JPG)

First Wordpress Blog:
![04](https://raw.githubusercontent.com/mohitagal98/hybrid-proj3/master/Images/blog.JPG)

