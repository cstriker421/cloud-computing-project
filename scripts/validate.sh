#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  ./scripts/validate.sh <client>
  ./scripts/validate.sh            # uses terraform outputs in ./terraform

Validates:
  - cluster reachable via kubeconfig
  - namespaces exist
  - odoo + db pods Ready
  - ingress hosts respond (expects 200/303/308 with eventual 200)
EOF
}

tf_output_raw() {
  local name="$1"
  [[ -d "terraform" ]] || return 1
  (cd terraform && terraform output -raw "$name" 2>/dev/null)
}

main() {
  local client="${1:-}"
  local kubeconfig=""
  local env_list=""

  if [[ -z "$client" ]]; then
    client="$(tf_output_raw client || true)"
    kubeconfig="$(tf_output_raw kubeconfig_path || true)"
    # NOTE: terraform output -raw doesn't work for list outputs reliably without jq.
    # Keep env list deterministic here to avoid extra dependencies.
  fi

  if [[ -z "$client" ]]; then
    usage
    echo "\nERROR: no <client> provided and couldn't read terraform outputs." >&2
    exit 2
  fi

  # If kubeconfig wasn't derived from outputs, assume repo layout
  if [[ -z "$kubeconfig" ]]; then
    kubeconfig="$PWD/terraform/.kube/${client}.config"
  fi

  if [[ ! -f "$kubeconfig" ]]; then
    echo "ERROR: kubeconfig not found: $kubeconfig" >&2
    echo "Hint: run 'terraform -chdir=terraform apply' for workspace '$client' first." >&2
    exit 2
  fi

  export KUBECONFIG="$kubeconfig"

  echo "[validate] Using KUBECONFIG=$KUBECONFIG"
  kubectl get nodes >/dev/null

  # Env mapping (keep in sync with terraform/variables.tf)
  case "$client" in
    airbnb)     env_list="dev prod" ;;
    nike)       env_list="dev qa prod" ;;
    mcdonalds)  env_list="dev qa beta prod" ;;
    *) echo "ERROR: unknown client '$client'" >&2; exit 2 ;;
  esac

  # Validate each env
  for env in $env_list; do
    ns="${client}-${env}"
    host="odoo.${env}.${client}.local"

    echo "[validate] Namespace: $ns"
    kubectl get namespace "$ns" >/dev/null

    echo "[validate] Pods Ready: $ns"
    kubectl -n "$ns" wait --for=condition=Ready pod -l app="${client}-${env}-db"   --timeout=180s >/dev/null
    kubectl -n "$ns" wait --for=condition=Ready pod -l app="${client}-${env}-odoo" --timeout=180s >/dev/null

    echo "[validate] Ingress reachable: https://$host"
    # -k to allow self-signed; -L to follow redirects
    code="$(curl -kLs -o /dev/null -w '%{http_code}' "https://${host}")"
    if [[ "$code" != "200" ]]; then
      echo "ERROR: expected 200 after redirects for https://$host, got $code" >&2
      exit 1
    fi
  done

  echo "[validate] OK: $client ($env_list)"
}

main "$@"
