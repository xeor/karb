#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-karb-e2e}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v kind >/dev/null 2>&1 || { echo "kind is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"
fi

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager --timeout=240s
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=240s
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-cainjector --timeout=240s

kubectl create namespace karb-system --dry-run=client -o yaml | kubectl apply -f -
