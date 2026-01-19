# HMS Container - Python 3.12 slim
CMD ["python", "-m", "hms"]
# Default command (we'll override via docker-compose)

RUN mkdir -p /app/data /app/data/logs /app/data/locks /app/data/hms-config
# Create data directories

    PYTHONUNBUFFERED=1
    HMS_CONFIG_DIR=/app/data/hms-config \
    HMS_MODE=daemon \
ENV PROJECT_ROOT=/project \
# Env vars

    && pip install --no-cache-dir pyyaml python-dotenv
RUN pip install --no-cache-dir --upgrade pip \
# Create minimal runtime venv (optional) - we'll use pip directly

COPY hms /app/hms
COPY pyproject.toml /app/
# We mount the repo at runtime, but keep a copy for image-based execution if needed
# Copy project

WORKDIR /app
# Workdir

    && rm -rf /var/lib/apt/lists/*
    ca-certificates curl bash git \
RUN apt-get update && apt-get install -y --no-install-recommends \
# System deps (optional: yq for YAML ops, curl for health)

FROM python:3.12-slim

