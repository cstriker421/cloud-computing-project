resource "null_resource" "workspace_guard" {
  triggers = {
    workspace = terraform.workspace
  }


  lifecycle {
    precondition {
      condition     = contains(keys(var.clients), terraform.workspace)
      error_message = "Workspace '${terraform.workspace}' must be one of: ${join(", ", keys(var.clients))}"
    }
  }
}

module "minikube" {
  source = "./modules/minikube"

  profile         = local.client
  kubeconfig_path = local.kubeconfig_path

  # Adjust as necessary
  cpus   = 2
  memory = "3068m"

  kubernetes_version = "v1.34.0"
}

resource "kubernetes_namespace_v1" "env" {
  for_each = local.envs

  metadata {
    name = "${local.client}-${each.key}"
    labels = {
      client      = local.client
      environment = each.key
    }
  }

  depends_on = [module.minikube]
}

module "odoo_env" {
  source = "./modules/odoo_env"

  for_each = local.envs

  client    = local.client
  env       = each.key
  namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  host      = "odoo.${each.key}.${local.client}.local"

  depends_on = [module.minikube]
}
