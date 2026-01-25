output "client" {
  description = "The active client name (terraform workspace)"
  value       = local.client
}

output "envs" {
  description = "Environments for the active client"
  value       = sort(tolist(local.envs))
}

output "kubeconfig_path" {
  description = "Path to the workspace-specific kubeconfig written by the minikube module"
  value       = module.minikube.kubeconfig_path
}

output "hostnames" {
  description = "Ingress hostnames for the active client"
  value       = [for e in sort(tolist(local.envs)) : "odoo.${e}.${local.client}.local"]
}

output "namespaces" {
  description = "Namespaces created for the active client"
  value       = [for e in sort(tolist(local.envs)) : "${local.client}-${e}"]
}
