FROM python:3.12-alpine

ENV PYTHONFAULTHANDLER=1 \
  PYTHONUNBUFFERED=1 \
  PYTHONHASHSEED=random \
  UV_SYSTEM_PYTHON=1 \
  UV_COMPILE_BYTECODE=1 \
  UV_LINK_MODE=copy

RUN pip install --no-cache-dir uv

WORKDIR /src
COPY pyproject.toml uv.lock /src/

RUN uv sync --frozen --no-dev

COPY src /src

CMD ["kopf", "run", "/src/main.py", "--verbose"]
