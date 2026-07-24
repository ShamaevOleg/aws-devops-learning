variable "eks_cluster_version" {
  type        = string
  description = "id of owner's image"
  default     = "1.36"
}

variable "allowed_ip_for_kubectl" {
  type        = string
  description = "CIDR allowed to reach cluster via kubectl. /32"

  validation {
    condition     = can(cidrhost(var.allowed_ip_for_kubectl, 0))
    error_message = "allowed_ip_subnet must be a valid CIDR, e.g. 203.0.113.4/32."
  }
}