variable "image_id" {
    type = string
    description = "list of image id"
}

variable "instance_type" {
    type = string
    default = "t3.micro"
    description = "type of instance"
}

variable "cidr_all" {
    type = string
    description = "cidr block for all addresses"
}

variable "allowed_ip_list" {
    type = string
    default = "127.0.0.1/32"
    description = "allowed IP mask"    
}

variable "aws_vpc_cidr_block" {
    type = string
    default = "10.0.0.0/16"
    description = "cidr_block for aws_vpc"
}

variable "aws_subnet_cidr_block" {
    type = string
    default = "10.0.1.0/24"
    description = "cidr_block for aws_subnet"
}

variable "public_key_path" {
    type = string
    default = "~/.ssh/file"
    description = "path to public key location"
}