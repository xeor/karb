#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-karb-e2e}"
TAG="${TAG:-e2e-local}"
IMAGE="ghcr.io/xeor/karb:${TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v kind >/dev/null 2>&1 || { echo "kind is required" >&2; exit 1; }
command -v podman >/dev/null 2>&1 || { echo "podman is required" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "Kind cluster '${CLUSTER_NAME}' does not exist. Run ./hack/kind-e2e/up.sh first." >&2
  exit 1
fi

podman build -f "${ROOT_DIR}/Containerfile" -t "${IMAGE}" "${ROOT_DIR}"

TMP_TAR="$(mktemp -t karb-kind-image.XXXXXX.tar)"
trap 'rm -f "${TMP_TAR}"' EXIT
podman save --format docker-archive -o "${TMP_TAR}" "${IMAGE}"
kind load image-archive --name "${CLUSTER_NAME}" "${TMP_TAR}"

helm upgrade --install karb "${ROOT_DIR}/charts/karb" \
  --namespace karb-system \
  -f "${SCRIPT_DIR}/values/karb-kind-values.yaml" \
  --set operator.image.tag="${TAG}"

kubectl -n karb-system rollout restart deployment/karb
kubectl -n karb-system rollout status deployment/karb --timeout=180s

echo "Loaded ${IMAGE} into kind/${CLUSTER_NAME} and restarted karb deployment."
