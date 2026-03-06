# AGENTS.md

## Purpose

This document defines how coding agents should work in this repository.
The project is being revived after a long maintenance gap, so prioritize:

1. Security hardening first.
2. Safe modernization with current stable dependencies.
3. Small, reviewable changes that keep the operator deployable.

## Repository Snapshot

- Language: Python (uv-managed)
- Runtime: Kubernetes operator based on `kopf`
- Main code path: `src/main.py`
- Test path: `tests/test_main.py`
- Deployment: Helm chart in `charts/karb`
- Container build: `Containerfile`
- Developer docs: `docs/`

## Non-Negotiable Rules

- Write all new code and documentation in English.
- Follow PEP 8 for Python code style.
- Prefer latest stable versions of dependencies.
- Do not weaken security defaults to "make things work".
- Never introduce secrets, tokens, kubeconfigs, or credentials into git.
- Keep changes minimal and scoped; avoid broad refactors unless requested.

## Dependency Policy (Upgrade Baseline)

- Use the newest stable release line for direct dependencies unless there is a clear compatibility blocker.
- Keep dependency definitions and lockfile in sync.
- After dependency changes, run at minimum:
  - `uv lock`
  - `uv sync --frozen`
  - `uv run pytest -q`
  - `uv run python -m py_compile src/main.py`
- If a new version is deferred, document why in the PR/commit message.

## Security-First Engineering Guidelines

### 1) Admission and Mutation Safety

- Treat all pod annotations as untrusted input.
- Validate and sanitize user-controlled values before using them:
  - `backup-name`
  - `backup-schedule`
  - shell/exec annotation values
- Reject unsafe values early with explicit errors.
- Avoid path traversal risks when composing filesystem or NFS paths.

### 2) Exec and Command Handling

- Minimize shell usage when possible.
- If shell execution is required, strictly validate command sources and format.
- Do not log sensitive command payloads or secrets.
- Ensure failures are visible via structured logs and metrics.

### 3) Kubernetes Least Privilege

- Preserve least-privilege RBAC; only add permissions with explicit justification.
- Keep container hardening enabled by default:
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true`
  - `runAsNonRoot: true`
  - drop all Linux capabilities
  - `seccompProfile: RuntimeDefault`
- Keep `automountServiceAccountToken` enabled only where required.

### 4) Secrets and Sensitive Data

- Never commit real hostnames, tokens, passwords, or private certificates.
- Use Kubernetes Secrets or runtime environment injection for sensitive values.
- Redact sensitive values in logs, examples, and docs.

### 5) Supply Chain and CI/CD

- Pin or update GitHub Actions to current secure versions.
- Keep base container images updated to supported stable tags.
- Prefer reproducible builds and deterministic dependency locking.
- Add or maintain dependency and image vulnerability scanning when possible.

## Coding Conventions for This Repo

- Keep operator behavior explicit and predictable.
- Prefer typed, testable helper functions for validation and parsing logic.
- Use descriptive error messages for operator events and logs.
- Avoid hidden side effects in mutation handlers.
- Preserve backward compatibility for existing chart values unless a breaking change is requested.

## Versioning and Tagging Policy

- Helm chart `version` must be bumped for every chart release.
- Helm chart `appVersion` must track the production container image tag.
- Default chart image tag should resolve to `appVersion` when no explicit tag is set in values.
- Git release tags follow `vX.Y.Z`; container publishing must produce `X.Y.Z` image tags.
- Keep package naming distinct in GHCR: container image at `ghcr.io/<owner>/karb`, OCI chart at `ghcr.io/<owner>/karb-chart`.

## Expected Validation Before Finishing a Change

For Python or operator logic changes:

- `uv lock`
- `uv sync --frozen`
- `uv run pytest -q`
- `uv run python -m py_compile src/main.py`

For Helm chart changes:

- `helm lint charts/karb`
- `helm template karb charts/karb`

For container/build changes:

- Build the image locally and confirm startup command still works.

## Suggested Modernization Backlog (Security-Focused)

When asked to continue the upgrade effort, prioritize this order:

1. Add strict annotation input validation (format, ranges, path safety).
2. Add automated linting/formatting/security tooling (Ruff, Bandit, pip-audit).
3. Add tests for mutation and backup scheduling behavior.
4. Tighten webhook behavior and failure handling based on desired safety model.
5. Refresh dependencies and CI actions to latest stable versions.

## Agent Output Expectations

- Explain what changed and why, with emphasis on security impact.
- Call out any compatibility risk and migration notes.
- If checks were not run, state exactly which checks are pending.
