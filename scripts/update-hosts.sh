#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  ./scripts/update-hosts.sh <client>
  ./scripts/update-hosts.sh --all

clients: airbnb | nike | mcdonalds
EOF
}

# env lists (keep in sync with terraform/variables.tf)
declare -A envs
envs[airbnb]="dev prod"
envs[nike]="dev qa prod"
envs[mcdonalds]="dev qa beta prod"

clients=("airbnb" "nike" "mcdonalds")

get_ip_for_client() {
  local client="$1"

  # 1) Prefers minikube profile IP if profile exists
  if minikube profile list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$client"; then
    minikube -p "$client" ip
    return 0
  fi

  # 2) Fallback: terraform output (recommended)
  # Expects terraform to run from repo root or within terraform
  if [[ -d "terraform" ]]; then
    (cd terraform && terraform output -raw minikube_ip 2>/dev/null) && return 0
  fi
  terraform output -raw minikube_ip 2>/dev/null && return 0

  echo "ERROR: Could not determine IP for client '$client'." >&2
  echo " - minikube profile '$client' not found" >&2
  echo " - terraform output 'minikube_ip' not found" >&2
  return 1
}

write_hosts_block() {
  local client="$1"
  local ip="$2"

  local start="# BEGIN ODOO HOSTS (${client})"
  local end="# END ODOO HOSTS (${client})"

  local block
  block="$(mktemp)"

  {
    echo "$start"
    for e in ${envs[$client]}; do
      echo "$ip odoo.$e.$client.local"
    done
    echo "$end"
  } > "$block"

  local tmp
  tmp="$(mktemp)"
  sudo cp /etc/hosts "$tmp"

  # Removes existing block if present, then appends new block
  awk -v start="$start" -v end="$end" '
    $0 == start {inblock=1; next}
    $0 == end   {inblock=0; next}
    !inblock {print}
  ' "$tmp" > "${tmp}.clean"

  cat "${tmp}.clean" "$block" | sudo tee /etc/hosts >/dev/null

  rm -f "$tmp" "${tmp}.clean" "$block"
}

main() {
  if [[ "${1:-}" == "--all" ]]; then
    for c in "${clients[@]}"; do
      if [[ -z "${envs[$c]:-}" ]]; then
        echo "ERROR: unknown client '$c' in script env map" >&2
        exit 2
      fi
      ip="$(get_ip_for_client "$c")"
      write_hosts_block "$c" "$ip"
      echo "Updated /etc/hosts for $c -> $ip"
    done
    exit 0
  fi

  local client="${1:-}"
  if [[ -z "$client" ]]; then usage; exit 2; fi
  if [[ -z "${envs[$client]:-}" ]]; then
    echo "ERROR: unknown client '$client' (expected: airbnb|nike|mcdonalds)" >&2
    exit 2
  fi

  ip="$(get_ip_for_client "$client")"
  write_hosts_block "$client" "$ip"
  echo "Updated /etc/hosts for $client -> $ip"
}

main "$@"
