variable "cidr_block" {
  type        = string
  description = "CIDR for aws_vpc resource for RDS"
}

variable "db_engine_version" {
  type        = string
  description = "DB engine version"
  default     = "16.14"
}