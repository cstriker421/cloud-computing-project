variable "client" { type = string }
variable "env" { type = string }
variable "namespace" { type = string }

variable "host" {
  description = "Ingress host, e.g. odoo.dev.airbnb.local"
  type        = string
}

variable "odoo_image" {
  type    = string
  default = "odoo:17"
}

variable "postgres_image" {
  type    = string
  default = "postgres:15"
}

variable "odoo_port" {
  type    = number
  default = 8069
}
