# Kind E2E Test Harness

This folder provides a simple end-to-end setup for testing the full `karb` flow on a local Kind cluster.

It validates:

- Helm installation of `karb`
- Admission mutation of annotated pods
- Init-container restore hook execution
- Scheduled backup command execution into the running container

## Prerequisites

- `kind`
- `kubectl`
- `helm`
- `podman`

## Quick Start

From the repository root:

```bash
./hack/kind-e2e/up.sh
./hack/kind-e2e/test.sh
```

To remove everything:

```bash
./hack/kind-e2e/down.sh
```

## Notes

- The Kind profile uses `hostPath` backend for backup storage in E2E to avoid local NFS kernel dependencies.
- The cluster name defaults to `karb-e2e`.
- The scripts are idempotent and safe to re-run.
