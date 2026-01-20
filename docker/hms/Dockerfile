# HMS Container - Python 3.12 slim
FROM python:3.12-slim

# System deps + Docker CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl bash git gnupg lsb-release \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
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

# Healthcheck para verificar que el scheduler esté funcionando
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c 'from hms.daemon.scheduler import get_scheduler; s=get_scheduler(); exit(0 if s else 1)' || exit 1

# Comando por defecto: Scheduler (daemon)
CMD ["python", "-m", "hms.daemon"]
