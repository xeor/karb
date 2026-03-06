# Release Readiness Checklist

## Mandatory Validation

- `uv lock`
- `uv sync --frozen`
- `uv run pytest -q`
- `uv run python -m py_compile src/main.py`
- `helm lint charts/karb`
- `helm template karb charts/karb`
- `podman build -f Containerfile .`

## Security Gates

- Annotation input validation rejects unsafe values (`backup-name`, schedule, shell)
- `hostPath` backend remains disabled by default
- RBAC includes only required verbs/resources
- Admission webhook failure policy explicitly reviewed (`Ignore` vs `Fail`)
- Runtime image pinned by digest

## Operational Gates

- Kind E2E passes (`task kind-up`, `task kind-test`)
- Tilt loop passes (`task dev`, `tilt trigger e2e-test`)
- No local-only values in production Helm values

## Known Pre-Prod Decisions

- Decide webhook `failurePolicy` (`charts/karb/templates/webhookconfiguration.yaml`)
- Confirm production storage backend (`nfs`) and disable `hostPath` in production values
