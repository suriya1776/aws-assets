provider "aws" {
  region = var.aws_region
}

###########################
# VARIABLES
###########################

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.10.1.0/26"
}

variable "public_subnets" {
  description = "List of public subnets with availability zone and CIDR block"
  type = list(object({
    az   = string
    cidr = string
  }))
  default = [
    { az = "ap-south-1a", cidr = "172.10.1.0/28" },
    { az = "ap-south-1b", cidr = "172.10.1.32/28" }
  ]
}

variable "private_subnets" {
  description = "List of private subnets with availability zone and CIDR block"
  type = list(object({
    az   = string
    cidr = string
  }))
  default = [
    { az = "ap-south-1a", cidr = "172.10.1.16/28" },
    { az = "ap-south-1b", cidr = "172.10.1.48/28" }
  ]
}

###########################
# VPC & DNS Settings
###########################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "dynamic-vpc"
  }
}

###########################
# Subnets
###########################

# Create public subnets with auto-assign public IPv4 enabled
resource "aws_subnet" "public" {
  for_each = { for subnet in var.public_subnets : "${subnet.az}-${subnet.cidr}" => subnet }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${each.value.az}"
  }
}

# Create private subnets (auto-assign public IPv4 remains disabled)
resource "aws_subnet" "private" {
  for_each = { for subnet in var.private_subnets : "${subnet.az}-${subnet.cidr}" => subnet }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "private-${each.value.az}"
  }
}

###########################
# Internet Gateway
###########################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "dynamic-igw"
  }
}

###########################
# Route Tables and Associations
###########################

# Public Route Table with default route to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Associate each public subnet with the public route table
resource "aws_route_table_association" "public_assoc" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table (without an IGW route)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "private-rt"
  }
}

# Associate each private subnet with the private route table
resource "aws_route_table_association" "private_assoc" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

###########################
# Replace Main Route Table Association
###########################

# Reassign the main route table of the VPC to our private route table.
# This effectively makes the default route table no longer used.
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.this.id
  route_table_id = aws_route_table.private.id
}

###########################
# OUTPUTS
###########################

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [for s in aws_subnet.private : s.id]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.igw.id
}
