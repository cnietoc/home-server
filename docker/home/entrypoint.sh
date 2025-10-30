#!/bin/sh

# Script de entrada que maneja dinámicamente PUID/PGID
set -e

# Usar variables de entorno o valores por defecto
PUID=${PUID:-1000}
PGID=${PGID:-1000}

echo "🔧 Configurando usuario con PUID=$PUID, PGID=$PGID"

# Crear grupo - manejar colisiones de GID
if ! getent group nodejs > /dev/null 2>&1; then
    # Verificar si el GID ya está en uso
    if getent group ${PGID} > /dev/null 2>&1; then
        EXISTING_GROUP=$(getent group ${PGID} | cut -d: -f1)
        echo "ℹ️ GID $PGID ya está en uso por grupo '$EXISTING_GROUP', usando grupo existente"
        GROUP_NAME=$EXISTING_GROUP
    else
        addgroup -g ${PGID} -S nodejs
        echo "✅ Grupo nodejs creado con GID=$PGID"
        GROUP_NAME=nodejs
    fi
else
    echo "ℹ️ Grupo nodejs ya existe"
    GROUP_NAME=nodejs
fi

# Crear usuario - manejar colisiones de UID
if ! getent passwd nodejs > /dev/null 2>&1; then
    # Verificar si el UID ya está en uso
    if getent passwd ${PUID} > /dev/null 2>&1; then
        EXISTING_USER=$(getent passwd ${PUID} | cut -d: -f1)
        echo "ℹ️ UID $PUID ya está en uso por usuario '$EXISTING_USER', usando usuario existente"
        USER_NAME=$EXISTING_USER
        # Agregar el usuario existente al grupo que vamos a usar
        adduser $USER_NAME $GROUP_NAME 2>/dev/null || true
    else
        adduser -S nodejs -u ${PUID} -G ${GROUP_NAME} -s /bin/sh
        echo "✅ Usuario nodejs creado con UID=$PUID"
        USER_NAME=nodejs
    fi
else
    echo "ℹ️ Usuario nodejs ya existe"
    USER_NAME=nodejs
fi

# Asegurar permisos correctos en /app
echo "🔧 Configurando permisos de /app..."
chown -R ${USER_NAME}:${GROUP_NAME} /app

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
        adduser ${USER_NAME} docker_host 2>/dev/null || true
        echo "✅ Usuario agregado al grupo docker del host"
    fi
else
    echo "⚠️ Docker no accesible (funcionará en modo degradado)"
fi

echo "🚀 Iniciando aplicación como usuario ${USER_NAME}..."

# Cambiar al usuario y ejecutar comando
exec su-exec ${USER_NAME} "$@"
