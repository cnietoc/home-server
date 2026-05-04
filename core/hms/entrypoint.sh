#!/usr/bin/env bash
# Entrypoint del contenedor HMS
# Lee config.toml y configura variables de entorno

set -euo pipefail

CONFIG_FILE="/app/config.toml"

# Función para parsear TOML usando yq
get_toml_value() {
    local file="$1"
    local path="$2"

    if [ -f "$file" ]; then
        yq eval "$path" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Leer valores de config.toml
if [ -f "$CONFIG_FILE" ]; then
    PUID=$(get_toml_value "$CONFIG_FILE" ".global.puid")
    PGID=$(get_toml_value "$CONFIG_FILE" ".global.pgid")
else
    echo "⚠️ config.toml no encontrado en $CONFIG_FILE"
    PUID=""
    PGID=""
fi

#Si el puid/pgid de la config no son los mismos que los del contenedor, fallar informando de que hay que recrear el contenedor
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
if [[ -n "$PUID" && "$PUID" != "$CURRENT_UID" ]]; then
    echo "❌ El PUID en config.toml ($PUID) no coincide con el UID del contenedor ($CURRENT_UID)."
    echo "   Por favor, ejecuta ""hms start"" para recrear el contenedor con el PUID correcto."
    exit 1
fi

if [[ -n "$PGID" && "$PGID" != "$CURRENT_GID" ]]; then
    echo "❌ El PGID en config.toml ($PGID) no coincide con el GID del contenedor ($CURRENT_GID)."
    echo "   Por favor, ejecuta ""hms start"" para recrear el contenedor con el PGID correcto."
    exit 1
fi

echo "👤 Ejecutando como UID=$(id -u) GID=$(id -g)"
exec "$@"
