# Update check: https://images.chainguard.dev/directory/image/python/versions
# NOTE: We intentionally use multi-arch tags here to avoid arch-specific digest mismatch in CI buildx.
FROM --platform=$TARGETPLATFORM cgr.dev/chainguard/python:latest-dev AS builder

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  UV_PROJECT_ENVIRONMENT=/opt/venv

USER root
WORKDIR /src
COPY pyproject.toml uv.lock /src/
RUN uv sync --frozen --no-dev

FROM --platform=$TARGETPLATFORM cgr.dev/chainguard/python:latest

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1 \
  PATH="/opt/venv/bin:${PATH}"

WORKDIR /src
COPY --from=builder /opt/venv /opt/venv
COPY src /src

USER 65532:65532
ENTRYPOINT []
CMD ["kopf", "run", "/src/main.py", "--verbose"]
