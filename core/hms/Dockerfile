# HMS Container - Python 3.12 slim
FROM python:3.12-slim

ARG PUID=1000
ARG PGID=1000

# ── System deps + Docker CLI + yq ────────────────────────────────────────────
# Capa que cambia raramente → va primero para máxima reutilización de caché
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

WORKDIR /app
ENV PYTHONPATH=/app \
    PROJECT_ROOT=/app \
    PYTHONUNBUFFERED=1

# ── Dependencias Python ───────────────────────────────────────────────────────
# Truco: stub mínimo del paquete para que hatchling pueda parsear pyproject.toml
# y descargar las deps SIN necesitar el código fuente real.
# Esta capa solo se invalida si cambia pyproject.toml, no con cada cambio de código.
COPY pyproject.toml /app/
RUN mkdir -p /app/hms && touch /app/hms/__init__.py \
    && pip install --no-cache-dir . \
    && rm -rf /app/hms

# ── Código fuente ─────────────────────────────────────────────────────────────
# Con cada cambio de código solo se re-ejecuta este paso (sin descargas).
COPY hms /app/hms
RUN pip install --no-cache-dir --no-deps .

# ── Archivos de soporte ───────────────────────────────────────────────────────
COPY config.default.toml /app/
COPY core/hms/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /.docker && chown -R ${PUID}:${PGID} /.docker

VOLUME ["/app/config.toml", "/app/logs", "/app/data", "/app/stacks", "/app/core", "/var/run/docker.sock"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "hms.daemon"]
