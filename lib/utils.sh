#!/usr/bin/env bash
# ============================================
# lib/utils.sh — Utilidades generales
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# ============================================
# UTILIDADES DE COMANDOS
# ============================================

# Obtener el prefijo del comando dinámicamente basándose en el path
# Útil para mensajes de ayuda que se adaptan a cómo se invocó el script
#
# Ejemplo:
#   Si el script es commands/stack/deploy → devuelve "hms stack deploy"
#   Si el script es commands/info/stack → devuelve "hms info stack"
#
# Uso:
#   local cmd_prefix=$(utils::get_command_prefix "${BASH_SOURCE[0]}")
#
utils::get_command_prefix() {
    local script_path="${1:-${BASH_SOURCE[1]}}"

    # Obtener el path absoluto real del script
    local script_real_path
    if [[ -L "$script_path" ]]; then
        script_real_path=$(readlink -f "$script_path" 2>/dev/null || realpath "$script_path" 2>/dev/null || echo "$script_path")
    else
        script_real_path=$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")
    fi

    # Si el script está en commands/, extraer la ruta relativa
    if [[ "$script_real_path" =~ /commands/(.+)$ ]]; then
        local cmd_path="${BASH_REMATCH[1]}"

        # Detectar si se está ejecutando a través de hms
        # usando la variable de entorno HMS_INVOKED que hms exporta
        if [[ "${HMS_INVOKED:-}" == "true" ]]; then
            # Se ejecuta a través de hms
            local hms_cmd=$(echo "$cmd_path" | tr '/' ' ')
            echo "hms $hms_cmd"
        else
            # Se ejecuta directamente - mostrar el path como se invocó
            # Si empieza con /, es absoluto, si no, es relativo
            if [[ "$script_path" =~ ^/ ]]; then
                echo "$script_path"
            else
                # Mostrar el path relativo desde donde se ejecutó
                echo "$script_path"
            fi
        fi
    else
        # Fallback: usar el nombre del script
        echo "$(basename "$script_path")"
    fi
}

