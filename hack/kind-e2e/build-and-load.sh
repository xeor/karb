#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?image reference is required}"
CLUSTER_NAME="${CLUSTER_NAME:-karb-e2e}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v podman >/dev/null 2>&1 || { echo "podman is required" >&2; exit 1; }
command -v kind >/dev/null 2>&1 || { echo "kind is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  "${SCRIPT_DIR}/bootstrap.sh"
fi

podman build -f "${ROOT_DIR}/Containerfile" -t "${IMAGE_REF}" "${ROOT_DIR}"

TMP_TAR="$(mktemp -t karb-kind-image.XXXXXX.tar)"
trap 'rm -f "${TMP_TAR}"' EXIT
podman save --format docker-archive -o "${TMP_TAR}" "${IMAGE_REF}"
kind load image-archive --name "${CLUSTER_NAME}" "${TMP_TAR}"

kubectl create namespace karb-system --dry-run=client -o yaml | kubectl apply -f -
kubectl -n karb-system delete pod karb-image-smoke --ignore-not-found
kubectl -n karb-system run karb-image-smoke \
  --image="${IMAGE_REF}" \
  --image-pull-policy=Never \
  --restart=Never \
  --command -- python -c "import time; time.sleep(5)"
if ! kubectl -n karb-system wait --for=condition=Ready pod/karb-image-smoke --timeout=90s; then
  kubectl -n karb-system describe pod karb-image-smoke >&2 || true
  kubectl -n karb-system logs karb-image-smoke >&2 || true
  exit 1
fi
kubectl -n karb-system delete pod karb-image-smoke --ignore-not-found
