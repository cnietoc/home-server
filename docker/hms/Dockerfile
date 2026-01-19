# HMS Container - Python 3.12 slim
FROM python:3.12-slim

# System deps (optional: yq for YAML ops, curl for health)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl bash git \
    && rm -rf /var/lib/apt/lists/*

# Workdir
WORKDIR /app

# Copy project
# We mount the repo at runtime, but keep a copy for image-based execution if needed
COPY pyproject.toml /app/
COPY hms /app/hms

# Create minimal runtime venv (optional) - we'll use pip directly
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir pyyaml python-dotenv

# Env vars
ENV PROJECT_ROOT=/project \
    HMS_MODE=daemon \
    HMS_CONFIG_DIR=/app/data/hms-config \
    PYTHONUNBUFFERED=1

# Create data directories
RUN mkdir -p /app/data /app/data/logs /app/data/locks /app/data/hms-config

# Default command (we'll override via docker-compose)
CMD ["python", "-m", "hms"]
