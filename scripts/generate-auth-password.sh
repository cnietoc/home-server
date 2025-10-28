#!/usr/bin/env bash

# Script de ayuda para generar hash de contraseñas para Authelia

set -euo pipefail

show_help() {
    cat << EOF
Uso: $0 [contraseña]

DESCRIPCIÓN:
  Genera un hash seguro para contraseñas de Authelia usando Argon2id.

EJEMPLOS:
  $0                          # Te pedirá la contraseña de forma segura
  $0 "mi-contraseña-segura"   # Genera hash para la contraseña especificada

NOTAS:
  - Si no especificas contraseña, se te pedirá de forma segura (sin mostrarla)
  - El hash generado debe reemplazarse en config/private/auth.env
  - Requiere Docker para funcionar
EOF
}

generate_password_hash() {
    local password="$1"

    echo "🔐 Generando hash seguro para Authelia..."
    echo ""

    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Error: Docker no está disponible"
        echo "Este script requiere Docker para generar el hash"
        exit 1
    fi

    local hash
    if hash=$(docker run --rm authelia/authelia:latest authelia hash-password "$password" 2>/dev/null); then
        echo "✅ Hash generado exitosamente:"
        echo ""
        echo "   $hash"
        echo ""
        echo "📋 Instrucciones:"
        echo "1. Copia el hash de arriba"
        echo "2. Edita: config/private/auth.env"
        echo "3. Reemplaza 'your-password-hash-here' en AUTHELIA_USERS_DATABASE con el hash copiado"
        echo "4. Guarda el archivo"
        echo "5. Regenera y despliega con:"
        echo "   ./scripts/deploy.sh --force-envs"
        echo "   ./scripts/deploy.sh auth --verbose"
    else
        echo "❌ Error generando hash"
        echo "Verifica que Docker esté corriendo y que tengas acceso a internet"
        exit 1
    fi
}

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        "")
            # Pedir contraseña de forma segura
            echo "🔐 Generador de Hash de Contraseñas para Authelia"
            echo "==============================================="
            echo ""
            echo -n "Ingresa la contraseña (no se mostrará): "
            read -s password
            echo ""
            echo ""

            if [[ -z "$password" ]]; then
                echo "❌ La contraseña no puede estar vacía"
                exit 1
            fi

            generate_password_hash "$password"
            ;;
        *)
            # Usar contraseña especificada
            generate_password_hash "$1"
            ;;
    esac
}

main "$@"
