# Development Guide

## Core Commands

- `task dev`: reset Kind cluster, bootstrap prerequisites, start Tilt
- `task test`: run unit tests (`uv run pytest -q`)
- `task kind-up`: bootstrap cluster + build/load image + deploy chart
- `task kind-test`: run end-to-end verification
- `task kind-load-image`: rebuild/reload image and restart operator
- `task kind-down`: delete Kind cluster
- `task release`: run release validations, create `vX.Y.Z` tag from chart version, push `main` and tag

## Unit Loop

```bash
uv sync --frozen
task test
uv run python -m py_compile src/main.py
```

## Kind E2E Loop

```bash
task kind-up
task kind-test
```

After operator/container changes:

```bash
task kind-load-image
task kind-test
```

## Image Iteration

`task kind-load-image` performs:

```bash
podman build -f Containerfile -t ghcr.io/xeor/karb:e2e-local .
podman save --format docker-archive -o /tmp/<archive>.tar ghcr.io/xeor/karb:e2e-local
kind load image-archive --name karb-e2e /tmp/<archive>.tar
helm upgrade --install karb charts/karb --namespace karb-system -f hack/kind-e2e/values/karb-kind-values.yaml --set operator.image.tag=e2e-local
kubectl -n karb-system rollout restart deployment/karb
```

## Debug Commands

```bash
kubectl -n karb-system logs deploy/karb --tail=300
kubectl get pod karb-e2e-app -n default -o yaml
kubectl auth can-i create pods/exec --as=system:serviceaccount:karb-system:karb-operator-account -n default
```

## Kind E2E Harness

Standalone script entrypoints:

```bash
./hack/kind-e2e/up.sh
./hack/kind-e2e/test.sh
./hack/kind-e2e/load-image.sh
./hack/kind-e2e/down.sh
```

Notes:

- Kind profile uses `hostPath` backend for local reliability.
- `KARB_ALLOW_HOSTPATH_BACKEND=true` is set only for Kind E2E values.
- Local test image ref is `ghcr.io/xeor/karb:e2e-local` and is loaded into Kind, not pushed.

## Tilt Workflow

Start:

```bash
task tilt-up
```

Target context: `kind-karb-e2e`

Tilt resources:

- `bootstrap-kind` (auto): cluster/cert-manager bootstrap
- `build-image` (auto): build + kind image load
- `karb` (k8s): Helm-rendered deploy
- `unit-tests` (auto)
- `py-compile` (auto)
- `e2e-test` (manual)
- `kind-down` (manual)

Useful triggers:

```bash
tilt trigger build-image
tilt trigger e2e-test
tilt trigger kind-down
```

Status/logs:

```bash
tilt get uiresources
tilt logs -f karb
```

Stop:

```bash
task tilt-down
```
