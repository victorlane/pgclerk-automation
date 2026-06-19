# Reusable AWS networking module. One VPC, one public subnet per AZ
# the caller hands in. Internet-egress only for now — no NAT.
# Returns the VPC id, subnet ids, and a security group that allows
# SSH from the operator's allow_ssh_cidr plus full intra-VPC traffic
# so PG nodes can talk to each other.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "name" {
  type        = string
  description = "Stable name prefix (usually <owner>-<cluster>)."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.42.0.0/16"
  description = "VPC IPv4 range."
}

variable "azs" {
  type        = list(string)
  description = "AZ suffixes to provision into (e.g. ['a','b','c'])."
}

variable "allow_ssh_cidr" {
  type        = string
  description = "Operator CIDR allowed to SSH into PG hosts."
}

variable "intra_pg_port" {
  type        = number
  default     = 5432
  description = "PG listen port. Intra-VPC only."
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = "${data.aws_region.current.name}${each.key}"
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, index(var.azs, each.key))
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.name}-public-${each.key}" })
}

data "aws_region" "current" {}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "pg" {
  name        = "${var.name}-pg-sg"
  description = "pgclerk: SSH from operator, PG intra-VPC, all egress."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Operator SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allow_ssh_cidr]
  }

  ingress {
    description = "PostgreSQL intra-VPC"
    from_port   = var.intra_pg_port
    to_port     = var.intra_pg_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "etcd peer + client (intra-VPC)"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Patroni REST API (intra-VPC)"
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-pg-sg" })
}

output "vpc_id"     { value = aws_vpc.this.id }
output "subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "pg_sg_id"   { value = aws_security_group.pg.id }
