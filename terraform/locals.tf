locals {
  client = terraform.workspace

  envs = toset(var.clients[local.client].environments)

  kubeconfig_path = "${path.root}/.kube/${local.client}.config"
}
