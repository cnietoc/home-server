#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common/env-loader.sh"

show_help() {
    cat << EOF
Uso: $0 [opciones]

DESCRIPCIÓN:
  Actualiza registros DNS de Cloudflare para apuntar a la IP actual del servidor.
  Crea automáticamente los registros A necesarios para el dominio base y wildcard.

OPCIONES:
  --ip IP               Usar IP específica (por defecto: detectar automáticamente)
  --domain DOMAIN       Dominio específico (por defecto: usar BASE_DOMAIN del config)
  --dry-run            Solo mostrar qué cambios se harían, sin aplicarlos
  --force              Forzar actualización aunque la IP no haya cambiado
  --list               Listar registros DNS actuales
  -v, --verbose        Mostrar información detallada
  -h, --help           Mostrar esta ayuda

EJEMPLOS:
  $0                              # Detectar IP y actualizar DNS automáticamente
  $0 --ip 192.168.1.100          # Usar IP específica
  $0 --dry-run                   # Ver qué cambios se harían
  $0 --domain ejemplo.com        # Actualizar dominio específico
  $0 --list                      # Ver registros DNS actuales

REQUISITOS:
  - Configuración de Cloudflare en config/private/cloudflare.env
  - BASE_DOMAIN configurado en config/private/common.env
  - Herramientas: curl, jq

REGISTROS QUE SE CREAN/ACTUALIZAN:
  - @ (dominio raíz)         → IP del servidor
  - * (wildcard)             → IP del servidor
EOF
}

# Detectar IP pública del servidor
get_public_ip() {
    local ip

    log "🔍 Detectando IP pública..."

    # Intentar varios servicios para obtener la IP
    local ip_services=(
        "https://api.ipify.org"
        "https://ipinfo.io/ip"
        "https://ifconfig.me"
        "https://api.my-ip.io/ip"
    )

    for service in "${ip_services[@]}"; do
        if ip=$(curl -s --max-time 10 "$service" 2>/dev/null); then
            # Validar que sea una IP válida
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log "✅ IP detectada: $ip (desde $(basename "$service"))"
                echo "$ip"
                return 0
            fi
        fi
    done

    log "❌ No se pudo detectar la IP pública"
    return 1
}

# Obtener Zone ID de Cloudflare
get_zone_id() {
    local domain="$1"
    local zone_id

    log "🔍 Obteniendo Zone ID para $domain..."

    local response
    if ! response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json" 2>/dev/null); then
        log "❌ Error conectando con Cloudflare API"
        return 1
    fi

    zone_id=$(echo "$response" | jq -r '.result[0].id // empty' 2>/dev/null)

    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        log "❌ No se encontró el dominio $domain en Cloudflare"
        log "Respuesta: $response"
        return 1
    fi

    log "✅ Zone ID obtenido: $zone_id"
    echo "$zone_id"
}

# Listar registros DNS actuales
list_dns_records() {
    local domain="$1"
    local zone_id

    if ! zone_id=$(get_zone_id "$domain"); then
        return 1
    fi

    log "📋 Registros DNS actuales para $domain:"

    local response
    if ! response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json"); then
        log "❌ Error obteniendo registros DNS"
        return 1
    fi

    echo "$response" | jq -r '.result[] | "\(.name) → \(.content) (TTL: \(.ttl), Proxy: \(.proxied))"' 2>/dev/null || {
        log "❌ Error procesando respuesta DNS"
        return 1
    }
}

# Obtener registro DNS específico
get_dns_record() {
    local zone_id="$1"
    local record_name="$2"
    local domain="$3"

    # Para el registro raíz, usar el dominio. Para wildcard, usar *
    local full_name="$record_name"
    if [[ "$record_name" == "@" ]]; then
        full_name="$domain"
    elif [[ "$record_name" == "*" ]]; then
        full_name="*.$domain"
    fi

    local response
    if ! response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$full_name" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json"); then
        return 1
    fi

    echo "$response" | jq -r '.result[0] // empty'
}

# Crear o actualizar registro DNS
update_dns_record() {
    local zone_id="$1"
    local record_name="$2"
    local ip="$3"
    local domain="$4"
    local dry_run="$5"
    local force="$6"

    # Para el registro raíz, usar el dominio. Para wildcard, usar *
    local full_name="$record_name"
    if [[ "$record_name" == "@" ]]; then
        full_name="$domain"
    elif [[ "$record_name" == "*" ]]; then
        full_name="*.$domain"
    fi

    log "🔍 Verificando registro: $full_name"

    local existing_record
    existing_record=$(get_dns_record "$zone_id" "$record_name" "$domain")

    if [[ -n "$existing_record" && "$existing_record" != "null" ]]; then
        local current_ip
        current_ip=$(echo "$existing_record" | jq -r '.content')
        local record_id
        record_id=$(echo "$existing_record" | jq -r '.id')

        if [[ "$current_ip" == "$ip" && "$force" != "true" ]]; then
            log "⏭️ $full_name ya apunta a $ip (sin cambios)"
            return 0
        fi

        log "🔄 Actualizando $full_name: $current_ip → $ip"

        if [[ "$dry_run" == "true" ]]; then
            log "🔥 [DRY-RUN] Se actualizaría: $full_name → $ip"
            return 0
        fi

        # Actualizar registro existente
        local update_data='{
            "type": "A",
            "name": "'$full_name'",
            "content": "'$ip'",
            "ttl": 300,
            "proxied": false
        }'

        local response
        if response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
            -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$update_data"); then

            local success
            success=$(echo "$response" | jq -r '.success')
            if [[ "$success" == "true" ]]; then
                log "✅ Actualizado: $full_name → $ip"
            else
                local errors
                errors=$(echo "$response" | jq -r '.errors[]?.message' 2>/dev/null || echo "Error desconocido")
                log "❌ Error actualizando $full_name: $errors"
                return 1
            fi
        else
            log "❌ Error de conectividad actualizando $full_name"
            return 1
        fi
    else
        log "➕ Creando nuevo registro: $full_name → $ip"

        if [[ "$dry_run" == "true" ]]; then
            log "🔥 [DRY-RUN] Se crearía: $full_name → $ip"
            return 0
        fi

        # Crear nuevo registro
        local create_data='{
            "type": "A",
            "name": "'$full_name'",
            "content": "'$ip'",
            "ttl": 300,
            "proxied": false
        }'

        local response
        if response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$create_data"); then

            local success
            success=$(echo "$response" | jq -r '.success')
            if [[ "$success" == "true" ]]; then
                log "✅ Creado: $full_name → $ip"
            else
                local errors
                errors=$(echo "$response" | jq -r '.errors[]?.message' 2>/dev/null || echo "Error desconocido")
                log "❌ Error creando $full_name: $errors"
                return 1
            fi
        else
            log "❌ Error de conectividad creando $full_name"
            return 1
        fi
    fi
}

# Verificar dependencias
check_dependencies() {
    local missing=()

    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "❌ Dependencias faltantes: ${missing[*]}"
        log "Instalar con: brew install ${missing[*]} (macOS) o apt install ${missing[*]} (Ubuntu)"
        return 1
    fi
}

# Función principal
main() {
    local target_ip=""
    local target_domain=""
    local dry_run=false
    local force=false
    local list_only=false
    local verbose=false

    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip)
                target_ip="$2"
                shift 2
                ;;
            --domain)
                target_domain="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "❌ Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Verificar dependencias
    if ! check_dependencies; then
        exit 1
    fi

    # Cargar configuración
    log "📂 Cargando configuración..."
    if ! load_common_config || ! load_secrets "cloudflare"; then
        log "❌ Error cargando configuración"
        exit 1
    fi

    # Verificar variables necesarias
    if [[ -z "${CF_DNS_API_TOKEN:-}" ]]; then
        log "❌ CF_DNS_API_TOKEN no configurado"
        log "Configura el token en config/private/cloudflare.env"
        exit 1
    fi

    # Usar dominio de configuración si no se especificó
    if [[ -z "$target_domain" ]]; then
        target_domain="${BASE_DOMAIN:-}"
        if [[ -z "$target_domain" ]]; then
            log "❌ BASE_DOMAIN no configurado y --domain no especificado"
            log "Configura BASE_DOMAIN en config/private/common.env"
            exit 1
        fi
    fi

    log "🌐 Dominio objetivo: $target_domain"

    # Solo listar registros si se pidió
    if [[ "$list_only" == "true" ]]; then
        list_dns_records "$target_domain"
        exit 0
    fi

    # Obtener IP objetivo
    if [[ -z "$target_ip" ]]; then
        if ! target_ip=$(get_public_ip); then
            exit 1
        fi
    else
        log "🎯 Usando IP especificada: $target_ip"
    fi

    # Obtener Zone ID
    local zone_id
    if ! zone_id=$(get_zone_id "$target_domain"); then
        exit 1
    fi

    # Registros a crear/actualizar
    local records=("@" "*")
    local success=0
    local total=${#records[@]}

    log "🚀 Actualizando registros DNS..."

    for record in "${records[@]}"; do
        if update_dns_record "$zone_id" "$record" "$target_ip" "$target_domain" "$dry_run" "$force"; then
            ((success++))
        fi
    done

    # Resumen final
    echo ""
    log "📊 Resultado: $success/$total registros procesados correctamente"

    if [[ "$dry_run" == "true" ]]; then
        log "🔥 Modo DRY-RUN: No se aplicaron cambios reales"
    elif [[ $success -eq $total ]]; then
        log "🎉 DNS actualizado correctamente"
        log "🌐 Servicios accesibles en:"
        log "   https://$target_domain"
        log "   https://*.$target_domain"
    else
        log "⚠️ Algunos registros tuvieron problemas"
        exit 1
    fi
}

main "$@"
