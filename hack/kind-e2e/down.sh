#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-karb-e2e}"

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  printf "Deleted cluster %s\n" "${CLUSTER_NAME}"
else
  printf "Cluster %s does not exist\n" "${CLUSTER_NAME}"
fi
