#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  ./scripts/update-hosts.sh <client>
  ./scripts/update-hosts.sh            # uses terraform outputs in ./terraform
  ./scripts/update-hosts.sh --all

clients: airbnb | nike | mcdonalds
EOF
}

# env lists (fallback; keep in sync with terraform/variables.tf)
declare -A envs
envs[airbnb]="dev prod"
envs[nike]="dev qa prod"
envs[mcdonalds]="dev qa beta prod"

clients=("airbnb" "nike" "mcdonalds")

get_ip_for_client() {
  local client="$1"

  if minikube profile list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$client"; then
    minikube -p "$client" ip
    return 0
  fi

  echo "ERROR: minikube profile '$client' not found (can't determine IP)." >&2
  return 1
}

tf_output_raw() {
  local name="$1"
  [[ -d "terraform" ]] || return 1
  (cd terraform && terraform output -raw "$name" 2>/dev/null)
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
  local env_list=""

  # No args? Derive from terraform outputs (recommended)
  if [[ -z "$client" ]]; then
    client="$(tf_output_raw client || true)"
    if [[ -z "$client" ]]; then
      usage
      echo "\nERROR: no <client> provided and couldn't read terraform outputs (run from repo root after 'terraform apply')." >&2
      exit 2
    fi
    env_list="$(tf_output_raw envs || true)"
  fi

  # Validate client
  if [[ " ${clients[*]} " != *" $client "* ]]; then
    echo "ERROR: unknown client '$client' (expected: airbnb|nike|mcdonalds)" >&2
    exit 2
  fi

  # Determine env list
  if [[ -z "$env_list" ]]; then
    env_list="${envs[$client]:-}"
  fi
  if [[ -z "$env_list" ]]; then
    echo "ERROR: no env list for client '$client'" >&2
    exit 2
  fi

  # Override envs map for this run
  envs[$client]="$env_list"

  ip="$(get_ip_for_client "$client")"
  write_hosts_block "$client" "$ip"
  echo "Updated /etc/hosts for $client -> $ip"
}

main "$@"
