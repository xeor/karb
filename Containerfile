# Update check: https://images.chainguard.dev/directory/image/python/versions
FROM cgr.dev/chainguard/python:3.14.3-dev@sha256:0f7e73dbdef70943ec7c23fdc2f0a29f8199de26cf8ee491e5d2a471041d5041 AS builder

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  UV_PROJECT_ENVIRONMENT=/opt/venv

USER root
WORKDIR /src
COPY pyproject.toml uv.lock /src/
RUN uv sync --frozen --no-dev

FROM cgr.dev/chainguard/python:3.14.3@sha256:3a4f55f57c8e9cf4b18412b261da7b1a2e1064899724fda9e859d455e3956c16

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
