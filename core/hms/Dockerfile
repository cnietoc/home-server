# HMS Container - Python 3.12 slim
FROM python:3.12-slim

# ===== Args para igualar UID/GID con el host =====
ARG PUID=1000
ARG PGID=1000

# System deps + Docker CLI + yq + gosu
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl bash git gnupg lsb-release wget \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq \
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

# Copiar archivos restantes
COPY config.default.toml /app/

# Variables de entorno
ENV PROJECT_ROOT=/app \
    PYTHONUNBUFFERED=1

# Copiar entrypoint
COPY core/hms/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME [ "/app/config.toml", "/app/logs", "/app/data" , "/app/stacks" , "/app/core", "/var/run/docker.sock"]

# Healthcheck: simple llamada HTTP al endpoint /api/health
HEALTHCHECK --interval=5m --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Crear carpeta de trabajo de docker y dar permisos
RUN mkdir -p /.docker && chown -R ${PUID}:${PGID} /.docker

# Entrypoint y comando por defecto
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "hms.daemon"]
