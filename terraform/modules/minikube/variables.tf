variable "profile" {
  description = "Minikube profile name (client/workspace name)."
  type        = string
}

variable "driver" {
  description = "Minikube driver."
  type        = string
  default     = "docker"
}

variable "cpus" {
  description = "CPUs for minikube."
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory for minikube (e.g. 4096m)."
  type        = string
  default     = "4096m"
}

variable "kubernetes_version" {
  description = "Kubernetes version to pin (optional)."
  type        = string
  default     = "" # empty => minikube default
}

variable "kubeconfig_path" {
  description = "Absolute or repo-relative kubeconfig path to write."
  type        = string
}

variable "addons" {
  description = "Minikube addons to enable."
  type        = list(string)
  default     = ["ingress"]
}
