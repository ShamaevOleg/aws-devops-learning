variable "image_owner_id" {
  type        = string
  description = "id of owner's image"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "type of instance"
}

variable "allowed_ip_subnet" {
  type        = string
  description = "CIDR allowed to reach SSH, /32"

  validation {
    condition     = can(cidrhost(var.allowed_ip_subnet, 0))
    error_message = "allowed_ip_subnet must be a valid CIDR, e.g. 203.0.113.4/32."
  }
}

variable "aws_vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "cidr_block for aws_vpc"
}

variable "aws_subnet_cidr_block" {
  type        = string
  default     = "10.0.1.0/24"
  description = "cidr_block for aws_subnet"
}
