resource "null_resource" "cluster" {
  triggers = {
    profile         = var.profile
    driver          = var.driver
    cpus            = tostring(var.cpus)
    memory          = var.memory
    kubeconfig_path = var.kubeconfig_path
    k8s_version     = var.kubernetes_version
    addons          = join(",", var.addons)
    script_rev      = "2026-01-25-minikube-module-1"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail

      profile="${self.triggers.profile}"
      kubeconfig_path="${self.triggers.kubeconfig_path}"

      mkdir -p "$(dirname "$kubeconfig_path")"

      echo "[minikube] Starting profile=$profile driver=${self.triggers.driver}"

      # Important: do NOT run as root; we're in devcontainer as vscode
      args=(
        start
        -p "$profile"
        --driver="${self.triggers.driver}"
        --container-runtime=containerd
        --cpus="${self.triggers.cpus}"
        --memory="${self.triggers.memory}"
      )

      if [ -n "${self.triggers.k8s_version}" ]; then
        args+=( --kubernetes-version="${self.triggers.k8s_version}" )
      fi

      minikube "$${args[@]}"

      echo "[minikube] Writing kubeconfig to $kubeconfig_path"
      # Writes a profile-specific kubeconfig file
      minikube -p "$profile" kubectl -- config view --raw > "$kubeconfig_path"

      # Enables addons (ingress required for rubric)
      IFS=',' read -r -a addons <<< "${self.triggers.addons}"
      for a in "$${addons[@]}"; do
        if [ -n "$a" ]; then
          echo "[minikube] Enabling addon: $a"
          minikube -p "$profile" addons enable "$a" >/dev/null
        fi
      done

      echo "[minikube] Waiting for node to be Ready..."
      KUBECONFIG="$kubeconfig_path" kubectl wait --for=condition=Ready node --all --timeout=180s

      # Ingress controller readiness
      echo "[minikube] Waiting for ingress controller (best effort)..."
      KUBECONFIG="$kubeconfig_path" kubectl -n ingress-nginx wait \
        --for=condition=Available deploy/ingress-nginx-controller --timeout=180s \
        2>/dev/null || true

      echo "[minikube] Cluster ready: $profile"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail
      profile="${self.triggers.profile}"
      echo "[minikube] Deleting profile=$profile"
      minikube delete -p "$profile" || true
    EOT
  }
}
