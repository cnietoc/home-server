# HMS Container - Python 3.12 slim
FROM python:3.12-slim

# System deps (curl/git opcional)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl bash git \
    && rm -rf /var/lib/apt/lists/*

# Workdir y PYTHONPATH
WORKDIR /app
ENV PYTHONPATH=/app

# Copiar proyecto
COPY pyproject.toml /app/
COPY hms /app/hms

# Instalación de deps y del paquete HMS
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

# Variables de entorno
ENV PROJECT_ROOT=/app \
    HMS_PATH=/app/hms \
    LOGS_PATH=/app/logs \
    DOCKER_PATH=/app/docker \
    DATA_PATH=/app/data \
    PYTHONUNBUFFERED=1

# Preparar directorios que se montarán como volúmenes
RUN mkdir -p /app/data /app/config /app/docker /app/logs
VOLUME ["/app/config", "/app/docker", "/app/data", "/app/logs"]

# Comando por defecto
CMD ["python", "-m", "hms"]
