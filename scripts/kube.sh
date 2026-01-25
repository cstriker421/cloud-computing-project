#!/usr/bin/env bash
set -euo pipefail

client="${1:-}"
shift || true

if [[ -z "$client" ]]; then
  echo "usage: ./scripts/kube.sh <client> <kubectl args...>"
  exit 1
fi

KCFG="$(pwd)/terraform/.kube/${client}.config"
if [[ ! -f "$KCFG" ]]; then
  echo "missing kubeconfig: $KCFG"
  exit 2
fi

KUBECONFIG="$KCFG" kubectl "$@"
