variable "prefix" {
    description = "The prefix that should be used for all resources"
    default = "web-server"
}

variable "vm_username" {
    description = "Database administrator username (\"admin\" is not possible)"
    type        = string
    sensitive   = true
}

variable "vm_password" {
    description = "Database administrator password"
    type        = string
    sensitive   = true
}

variable "location" {
    description = "The Azure Region in which alle resources are created"
    default = "East US"
}

variable "instances" {
    description = "The VM instances to be created"
    default = ["vm1", "vm2"]
}
