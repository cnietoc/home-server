#!/bin/sh

# Script de entrada que maneja dinámicamente PUID/PGID
set -e

# Usar variables de entorno o valores por defecto
PUID=${PUID:-1000}
PGID=${PGID:-1000}

echo "🔧 Configurando usuario con PUID=$PUID, PGID=$PGID"

# Crear grupo si no existe
if ! getent group nodejs > /dev/null 2>&1; then
    addgroup -g ${PGID} -S nodejs
    echo "✅ Grupo nodejs creado con GID=$PGID"
else
    echo "ℹ️ Grupo nodejs ya existe"
fi

# Crear usuario si no existe
if ! getent passwd nodejs > /dev/null 2>&1; then
    adduser -S nodejs -u ${PUID} -G nodejs -s /bin/sh
    echo "✅ Usuario nodejs creado con UID=$PUID"
else
    echo "ℹ️ Usuario nodejs ya existe"
fi

# Asegurar permisos correctos en /app
echo "🔧 Configurando permisos de /app..."
chown -R nodejs:nodejs /app

# Verificar acceso a Docker
echo "🐳 Verificando acceso a Docker..."
if docker version >/dev/null 2>&1; then
    echo "✅ Docker accesible"

    # Agregar usuario al grupo docker del host si existe
    DOCKER_GID=$(stat -c %g /var/run/docker.sock 2>/dev/null || echo "")
    if [ -n "$DOCKER_GID" ]; then
        echo "🔧 Agregando usuario al grupo docker (GID=$DOCKER_GID)..."
        if ! getent group docker_host > /dev/null 2>&1; then
            addgroup -g ${DOCKER_GID} -S docker_host
        fi
        adduser nodejs docker_host 2>/dev/null || true
        echo "✅ Usuario agregado al grupo docker del host"
    fi
else
    echo "⚠️ Docker no accesible (funcionará en modo degradado)"
fi

echo "🚀 Iniciando aplicación como usuario nodejs..."

# Cambiar al usuario nodejs y ejecutar comando
exec su-exec nodejs "$@"
