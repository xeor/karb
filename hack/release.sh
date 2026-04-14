#!/usr/bin/env bash
set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Missing required command: %s\n" "$1" >&2
    exit 1
  }
}

for bin in git uv helm awk python3; do
  require "$bin"
done

printf "Release preflight: stage or commit all release changes before running this task.\n"
printf "If you have unstaged changes, stop and stage/commit them first.\n"

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${branch}" != "main" ]]; then
  printf "Release must run from 'main' branch. Current: %s\n" "${branch}" >&2
  exit 1
fi

release_version="${1:-}"

if [[ -z "${release_version}" ]]; then
  printf "Usage: ./hack/release.sh X.Y.Z\n" >&2
  printf "Example: task release VERSION=1.0.4\n" >&2
  exit 1
fi

if [[ ! "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf "Release version must be SemVer (X.Y.Z). Found: %s\n" "${release_version}" >&2
  exit 1
fi

unstaged_changes="$(git diff --name-only)"
untracked_changes="$(git ls-files --others --exclude-standard)"

if [[ -n "${unstaged_changes}" || -n "${untracked_changes}" ]]; then
  printf "Found unstaged or untracked files. Stage or commit release changes before running release.\n" >&2
  printf "Hint: git add -A && git status\n" >&2
  exit 1
fi

chart_file="charts/karb/Chart.yaml"
values_file="charts/karb/values.yaml"

python3 - "${chart_file}" "${values_file}" "${release_version}" <<'PY'
from pathlib import Path
import sys

chart_path = Path(sys.argv[1])
values_path = Path(sys.argv[2])
version = sys.argv[3]

chart_lines = chart_path.read_text(encoding="utf-8").splitlines()
updated_chart = []
for line in chart_lines:
    if line.startswith("version:"):
        updated_chart.append(f"version: {version}")
    elif line.startswith("appVersion:"):
        updated_chart.append(f"appVersion: {version}")
    else:
        updated_chart.append(line)

values_lines = values_path.read_text(encoding="utf-8").splitlines()
updated_values = []
inside_image_block = False
for line in values_lines:
    if line.startswith("  image:"):
        inside_image_block = True
        updated_values.append(line)
        continue

    if inside_image_block and line.startswith("    tag:"):
        updated_values.append(f"    tag: \"{version}\"")
        continue

    if inside_image_block and not line.startswith("    "):
        inside_image_block = False

    updated_values.append(line)

chart_path.write_text("\n".join(updated_chart) + "\n", encoding="utf-8")
values_path.write_text("\n".join(updated_values) + "\n", encoding="utf-8")
PY

git add "${chart_file}" "${values_file}"

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

if [[ "${chart_version}" != "${release_version}" ]]; then
  printf "Chart version (%s) and release version (%s) must match.\n" "${chart_version}" "${release_version}" >&2
  printf "Update charts/karb/Chart.yaml version/appVersion before releasing.\n" >&2
  exit 1
fi

release_tag="v${release_version}"

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

if [[ -n "$(git diff --cached --name-only)" ]]; then
  printf "Creating release commit for staged changes...\n"
  git commit -m "release: ${release_tag}"
fi

printf "Creating release tag %s...\n" "${release_tag}"
git tag -a "${release_tag}" -m "Release ${release_tag}"

printf "Pushing main and %s...\n" "${release_tag}"
git push origin main
git push origin "${release_tag}"

printf "Release pushed.\n"
printf "Container workflow will publish image tags from: %s\n" "${release_version}"
printf "Chart workflow will publish OCI chart: oci://ghcr.io/<owner>/karb-chart --version %s\n" "${release_version}"
