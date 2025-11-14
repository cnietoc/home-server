#!/usr/bin/env bash
# ============================================
# lib/logs.sh — Logging con rotación diaria
# ============================================

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    echo "❌ Este archivo es una librería y no debe ejecutarse directamente." >&2
    exit 1
}

# --- Colores ANSI ---
RESET="\033[0m"
# Colores normales sin bold
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;36m"
GREEN="\033[0;32m"
GRAY="\033[0;90m"
# Solo para símbolos
BOLD_RED="\033[1;31m"
BOLD_GREEN="\033[1;32m"
BOLD_YELLOW="\033[1;33m"

# --- Configuración por defecto ---
# Detectar PROJECT_ROOT automáticamente
# Este archivo está en PROJECT_ROOT/lib/logs.sh
_LOGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LOGS_PROJECT_ROOT="$(dirname "$_LOGS_LIB_DIR")"

LOG_DIR="${LOG_DIR:-${_LOGS_PROJECT_ROOT}/data/logs}"    # Carpeta de logs en data/logs
LOG_FILE="${LOG_FILE:-${LOG_DIR}/hms.log}"               # Archivo del día actual
LOG_LEVEL="${LOG_LEVEL:-INFO}"                           # Nivel mínimo
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"            # Número de días a mantener
_logs_current_day=""                                     # Día actual para detectar cambios

# --- Función interna: timestamp ---
_logs::timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# --- Función interna: rotación al cambiar de día ---
_logs::rotate_if_needed() {
    local today=$(date +%Y-%m-%d)

    mkdir -p "$LOG_DIR"

    # Si cambió el día y existe el log anterior
    if [[ -n "$_logs_current_day" && "$today" != "$_logs_current_day" && -f "$LOG_FILE" ]]; then
        # Mover el log del día anterior con su fecha
        mv "$LOG_FILE" "${LOG_DIR}/hms_${_logs_current_day}.log"

        # Limpiar logs antiguos
        find "$LOG_DIR" -maxdepth 1 -name "hms_*.log" -type f \
            -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    fi

    # Actualizar día actual
    _logs_current_day="$today"
}

# --- Función interna: escribir log ---
_logs::write() {
    local level="$1"; shift
    local symbol="$1"; shift
    local color="$1"; shift
    local msg="$*"
    local ts=$(_logs::timestamp)

    # Rotar si cambió el día
    _logs::rotate_if_needed

    # Línea para archivo (sin colores)
    local file_line="${ts} [${level}] ${msg}"

    # Línea para consola (con colores sutiles)
    local console_line="${GRAY}${ts}${RESET} ${symbol} ${color}${msg}${RESET}"

    # Escribir
    echo -e "$console_line"
    echo "$file_line" >> "$LOG_FILE"
}

# --- Funciones públicas ---
logs::debug() {
    [[ "$LOG_LEVEL" == "DEBUG" ]] && _logs::write "DEBUG" "${GRAY}🔍${RESET}" "$GRAY" "$*"
}

logs::info() {
    _logs::write "INFO" "${BLUE}ℹ${RESET}" "$RESET" "$*"
}

logs::ok() {
    _logs::write "OK" "${BOLD_GREEN}✓${RESET}" "$GREEN" "$*"
}

logs::warn() {
    _logs::write "WARN" "${BOLD_YELLOW}⚠${RESET}" "$YELLOW" "$*"
}

logs::error() {
    _logs::write "ERROR" "${BOLD_RED}✗${RESET}" "$RED" "$*"
}

