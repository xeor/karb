#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl -n karb-system wait --for=condition=Available deployment/karb --timeout=180s

kubectl delete pod karb-e2e-app -n default --ignore-not-found
kubectl wait --for=delete pod/karb-e2e-app -n default --timeout=120s || true

kubectl apply -f "${SCRIPT_DIR}/manifests/test-pod.yaml"
kubectl wait --for=condition=Ready pod/karb-e2e-app -n default --timeout=180s

init_names="$(kubectl get pod karb-e2e-app -n default -o jsonpath='{.spec.initContainers[*].name}')"
if [[ "${init_names}" != *"karb-restorer"* ]]; then
  printf "Expected init container 'karb-restorer', got: %s\n" "${init_names}" >&2
  exit 1
fi

volume_names="$(kubectl get pod karb-e2e-app -n default -o jsonpath='{.spec.volumes[*].name}')"
if [[ "${volume_names}" != *"karb-backup-volume"* ]]; then
  printf "Expected volume 'karb-backup-volume', got: %s\n" "${volume_names}" >&2
  exit 1
fi

restore_marker="$(kubectl exec -n default karb-e2e-app -c app -- cat /karb-data/restore-ran 2>/dev/null || true)"
if [[ "${restore_marker}" != "restore-ran" ]]; then
  printf "Restore marker not found on shared backup volume.\n" >&2
  kubectl logs -n default karb-e2e-app -c karb-restorer --tail=200 >&2 || true
  exit 1
fi

attempt=0
backup_lines=0
while [[ ${attempt} -lt 18 ]]; do
  backup_lines="$(kubectl exec -n default karb-e2e-app -c app -- sh -c 'wc -l < /karb-data/backup.log' 2>/dev/null || echo 0)"
  if [[ "${backup_lines}" =~ ^[0-9]+$ ]] && [[ ${backup_lines} -ge 1 ]]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 5
done

if [[ ! "${backup_lines}" =~ ^[0-9]+$ ]] || [[ ${backup_lines} -lt 1 ]]; then
  printf "No backup entries written after waiting.\n" >&2
  kubectl logs -n karb-system deploy/karb --tail=200 >&2 || true
  exit 1
fi

printf "E2E test passed. backup.log lines: %s\n" "${backup_lines}"
