FROM python:3.12-slim AS builder

# sqlcipher build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libsqlcipher-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock* .python-version ./
RUN uv sync --frozen --no-dev --no-install-project --extra sqlcipher || \
    uv sync --no-dev --no-install-project --extra sqlcipher

COPY src/ src/
RUN uv sync --frozen --no-dev --extra sqlcipher || \
    uv sync --no-dev --extra sqlcipher


FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlcipher0 \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r igris && useradd -r -g igris -d /app -s /sbin/nologin igris

WORKDIR /app
COPY --from=builder /app /app

RUN mkdir -p /data && chown igris:igris /data

USER igris

EXPOSE 8920

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8920/health')" || exit 1

ENTRYPOINT ["uv", "run", "uvicorn", "igris.main:app", "--host", "0.0.0.0", "--port", "8920"]
