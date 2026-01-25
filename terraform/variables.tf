variable "clients" {
  description = "Client definitions and their environments. Workspace name must match a key in this map."
  type = map(object({
    environments = list(string)
  }))

  default = {
    airbnb    = { environments = ["dev", "prod"] }
    nike      = { environments = ["dev", "qa", "prod"] }
    mcdonalds = { environments = ["dev", "qa", "beta", "prod"] }
  }
}
