#!/usr/bin/env bash
set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Missing required command: %s\n" "$1" >&2
    exit 1
  }
}

for bin in git uv helm awk; do
  require "$bin"
done

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${branch}" != "main" ]]; then
  printf "Release must run from 'main' branch. Current: %s\n" "${branch}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  printf "Working tree must be clean before release.\n" >&2
  exit 1
fi

chart_file="charts/karb/Chart.yaml"
chart_version="$(awk '/^version:/ {print $2}' "${chart_file}")"
app_version="$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2}' "${chart_file}")"

if [[ -z "${chart_version}" || -z "${app_version}" ]]; then
  printf "Unable to read version/appVersion from %s\n" "${chart_file}" >&2
  exit 1
fi

if [[ "${chart_version}" != "${app_version}" ]]; then
  printf "Chart version (%s) and appVersion (%s) must match for release.\n" "${chart_version}" "${app_version}" >&2
  exit 1
fi

if [[ ! "${chart_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf "Release version must be SemVer (X.Y.Z). Found: %s\n" "${chart_version}" >&2
  exit 1
fi

release_tag="v${chart_version}"

if git rev-parse -q --verify "refs/tags/${release_tag}" >/dev/null; then
  printf "Tag %s already exists locally.\n" "${release_tag}" >&2
  exit 1
fi

if git ls-remote --tags origin "refs/tags/${release_tag}" | grep -q "${release_tag}"; then
  printf "Tag %s already exists on origin.\n" "${release_tag}" >&2
  exit 1
fi

printf "Running release validation...\n"
uv lock --check
uv sync --frozen
uv run pytest -q
uv run python -m py_compile src/main.py
helm lint charts/karb
helm template karb charts/karb >/dev/null

printf "Creating release tag %s...\n" "${release_tag}"
git tag -a "${release_tag}" -m "Release ${release_tag}"

printf "Pushing main and %s...\n" "${release_tag}"
git push origin main
git push origin "${release_tag}"

printf "Release pushed.\n"
printf "Container workflow will publish image tags from: %s\n" "${chart_version}"
printf "Chart workflow will publish OCI chart: oci://ghcr.io/<owner>/karb-chart --version %s\n" "${chart_version}"
