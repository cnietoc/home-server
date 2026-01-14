#!/bin/bash
# entrypoint.sh - Inicialización de ASF con configuración desde variables de entorno

set -e

CONFIG_DIR="/app/config"
ASF_CONFIG="${CONFIG_DIR}/ASF.json"
BOT_CONFIG="${CONFIG_DIR}/DefaultBot.json"

# Crear directorio de config
mkdir -p "${CONFIG_DIR}"

# Generar ASF.json desde template si no existe
if [ ! -f "${ASF_CONFIG}" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Generando ASF.json desde template..."

  if [ -f "/app/ASF.json" ]; then
    envsubst < /app/ASF.json > "${ASF_CONFIG}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ASF.json generado exitosamente"
  else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: ASF.json no encontrado"
    exit 1
  fi
else
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ASF.json ya existe, usando configuración existente"
fi

# Generar DefaultBot.json desde template si no existe
if [ ! -f "${BOT_CONFIG}" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Generando DefaultBot.json desde template..."

  # Validar credenciales
  if [ -z "${STEAM_USERNAME}" ] || [ -z "${STEAM_PASSWORD}" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: STEAM_USERNAME y STEAM_PASSWORD son requeridos"
    exit 1
  fi

  if [ -f "/app/DefaultBot.json" ]; then
    envsubst < /app/DefaultBot.json > "${BOT_CONFIG}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] DefaultBot.json generado exitosamente"
  else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: DefaultBot.json no encontrado"
    exit 1
  fi
else
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] DefaultBot.json ya existe, usando configuración existente"
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Iniciando ArchiSteamFarm..."

# Ejecutar ASF
exec "$@"

