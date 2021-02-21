
variable app_name {
  type    = string
  default = "app1"
}

variable bigip_count {
  default = 0
}

variable prefix {
  description = "Prefix for resources created by this module"
  type        = string
  default     = "student"
}

variable location {default = "East US"}

variable cidr {
  description = "Azure VPC CIDR"
  type        = string
  default     = "10.2.0.0/16"
}

variable upassword {default = "F5student!"}

variable availabilityZones {
  description = "If you want the VM placed in an Azure Availability Zone, and the Azure region you are deploying to supports it, specify the numbers of the existing Availability Zone you want to use."
  type        = list
  default     = [2]
}
variable AllowedIPs {}

# TAGS
variable "purpose" { default = "public" }
variable "environment" { default = "f5env" } #ex. dev/staging/prod
variable "owner" { default = "f5owner" }
variable "group" { default = "f5group" }
variable "costcenter" { default = "f5costcenter" }
variable "application" { default = "f5app" }
