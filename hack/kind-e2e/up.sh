#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-karb-e2e}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.18.2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Missing required command: %s\n" "$1" >&2
    exit 1
  }
}

for bin in kind kubectl helm podman; do
  require "$bin"
done

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"
fi

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager --timeout=240s
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=240s
kubectl -n cert-manager wait --for=condition=Available deployment/cert-manager-cainjector --timeout=240s

kubectl create namespace karb-system --dry-run=client -o yaml | kubectl apply -f -

podman build -f "${ROOT_DIR}/Containerfile" -t ghcr.io/xeor/karb:e2e-local "${ROOT_DIR}"

TMP_TAR="$(mktemp -t karb-e2e-image.XXXXXX.tar)"
trap 'rm -f "${TMP_TAR}"' EXIT
podman save --format docker-archive -o "${TMP_TAR}" ghcr.io/xeor/karb:e2e-local
kind load image-archive --name "${CLUSTER_NAME}" "${TMP_TAR}"

kubectl -n karb-system delete pod karb-image-smoke --ignore-not-found
kubectl -n karb-system run karb-image-smoke \
  --image=ghcr.io/xeor/karb:e2e-local \
  --image-pull-policy=Never \
  --restart=Never \
  --command -- python -c "import time; time.sleep(15)"
kubectl -n karb-system wait --for=condition=Ready pod/karb-image-smoke --timeout=90s
kubectl -n karb-system delete pod karb-image-smoke --ignore-not-found

helm upgrade --install karb "${ROOT_DIR}/charts/karb" \
  --namespace karb-system \
  -f "${SCRIPT_DIR}/values/karb-kind-values.yaml"

kubectl -n karb-system wait --for=condition=Available deployment/karb --timeout=180s

printf "Cluster is ready. Run: %s/test.sh\n" "${SCRIPT_DIR}"
