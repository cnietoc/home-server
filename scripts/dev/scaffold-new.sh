#!/usr/bin/env bash
# ============================================
# scripts/dev/scaffold-new.sh
# Crea la NUEVA estructura de comandos HMS
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMANDS_DIR="$PROJECT_ROOT/commands"

# Colores
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;36m"
RESET="\033[0m"

echo -e "${BLUE}🏗️  Creando nueva estructura de comandos HMS...${RESET}"
echo ""

# Template base para comandos WIP
create_wip_command() {
    local category="$1"
    local command="$2"
    local description="$3"
    local legacy_script="${4:-}"
    local file_path="$COMMANDS_DIR/$category/$command"

    # Crear directorio si no existe
    mkdir -p "$COMMANDS_DIR/$category"

    # Crear archivo solo si no existe
    if [[ -f "$file_path" ]]; then
        echo -e "${YELLOW}⏭️  Saltando $category/$command (ya existe)${RESET}"
        return
    fi

    cat > "$file_path" << 'TEMPLATE_END'
#!/usr/bin/env bash
# ============================================
# commands/CATEGORY/COMMAND — DESCRIPTION
# ============================================
# Estado: 🚧 WIP (Work In Progress)
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/lib/logs.sh"
source "$PROJECT_ROOT/lib/utils.sh"

# ============================================
# MAIN
# ============================================

main() {
    local cmd_prefix=$(utils::get_command_prefix "${BASH_SOURCE[0]}")

    logs::warn "🚧 Este comando está en desarrollo (WIP)"
    echo ""
    logs::info "📋 Comando: ${cmd_prefix}"
    logs::info "📝 Descripción: DESCRIPTION"
    echo ""
LEGACY_BLOCK
    logs::error "⏳ Implementación pendiente"
    echo ""
}

main "$@"
TEMPLATE_END

    # Reemplazar placeholders
    sed -i.bak "s|CATEGORY|$category|g" "$file_path" && rm "${file_path}.bak"
    sed -i.bak "s|COMMAND|$command|g" "$file_path" && rm "${file_path}.bak"
    sed -i.bak "s|DESCRIPTION|$description|g" "$file_path" && rm "${file_path}.bak"

    # Agregar script legacy si existe
    if [[ -n "$legacy_script" ]]; then
        local legacy_block="    logs::info \"💡 Mientras tanto, puedes usar el script legacy:\"\n    logs::info \"   $legacy_script\"\n    echo \"\""
        sed -i.bak "s|LEGACY_BLOCK|$legacy_block|g" "$file_path" && rm "${file_path}.bak"
    else
        sed -i.bak "s|LEGACY_BLOCK||g" "$file_path" && rm "${file_path}.bak"
    fi

    # Dar permisos de ejecución
    chmod +x "$file_path"

    echo -e "${GREEN}✅ Creado $category/$command${RESET}"
}

# ============================================
# CREAR COMANDOS - NUEVA ESTRUCTURA
# ============================================

# SHOW commands (renombrado de info)
echo -e "${BLUE}📊 Creando comandos show/...${RESET}"
create_wip_command "show" "status" "Estado de deployments" "./scripts/stack-state.sh status [stack]"
create_wip_command "show" "logs" "Ver logs de stacks" "docker compose -f docker/<stack>/docker-compose.yml logs -f"
create_wip_command "show" "config" "Configuración actual de stacks" "./scripts/generate-docker-envs.sh --list"
create_wip_command "show" "health" "Health checks de servicios" ""

# DEPLOY commands
echo -e "${BLUE}🚀 Creando comandos deploy/...${RESET}"
create_wip_command "deploy" "up" "Iniciar/deploy stacks" "./scripts/deploy.sh [stack]"
create_wip_command "deploy" "down" "Parar stacks" "docker compose down"
create_wip_command "deploy" "restart" "Reiniciar stacks" "docker compose restart"
create_wip_command "deploy" "enable" "Habilitar stack para deployment" "./scripts/stack-state.sh enable_stack <stack>"
create_wip_command "deploy" "disable" "Deshabilitar stack" "./scripts/stack-state.sh disable_stack <stack>"
create_wip_command "deploy" "clean" "Deploy limpio eliminando recursos" "./scripts/clean-deploy.sh"
create_wip_command "deploy" "auto" "Deploy automático (CI/CD)" "./scripts/auto-deploy.sh"

# CONFIG commands
echo -e "${BLUE}⚙️  Creando comandos config/...${RESET}"
create_wip_command "config" "generate" "Generar archivos .env" "./scripts/generate-docker-envs.sh"
create_wip_command "config" "validate" "Validar archivos de configuración" ""
create_wip_command "config" "link" "Gestionar enlaces simbólicos de configuración" "./scripts/link.sh"
create_wip_command "config" "edit" "Abrir archivos de configuración para editar" ""

# BACKUP commands
echo -e "${BLUE}💾 Creando comandos backup/...${RESET}"
create_wip_command "backup" "create" "Crear backup" "./scripts/backup.sh"
create_wip_command "backup" "restore" "Restaurar backup" "./scripts/backup.sh restore <backup-file>"
create_wip_command "backup" "list" "Listar backups disponibles" ""
create_wip_command "backup" "schedule" "Configurar backups automáticos" ""

# SETUP commands
echo -e "${BLUE}🔧 Creando comandos setup/...${RESET}"
create_wip_command "setup" "init" "Setup completo inicial" ""
create_wip_command "setup" "docker" "Instalar/configurar Docker" "./scripts/install-docker.sh"
create_wip_command "setup" "networks" "Configurar redes Docker" "./scripts/setup-networks.sh"
create_wip_command "setup" "security" "Configurar seguridad del sistema" "./scripts/setup-security.sh"
create_wip_command "setup" "ssh" "Configuración SSH" "./scripts/setup-ssh.sh"
create_wip_command "setup" "nfs" "Configurar/gestionar NFS" "./scripts/nfs-manager.sh"
create_wip_command "setup" "onedrive" "Configurar/gestionar OneDrive" "./scripts/onedrive-manager.sh"

# MAINTAIN commands
echo -e "${BLUE}🔨 Creando comandos maintain/...${RESET}"
create_wip_command "maintain" "clean" "Limpieza de recursos Docker" "docker system prune -a"
create_wip_command "maintain" "update" "Actualizar componentes del sistema" "./scripts/update-dns.sh"
create_wip_command "maintain" "check" "Verificación de salud del sistema" "./scripts/check-hw-accel.sh"
create_wip_command "maintain" "auto" "Mantenimiento automático" "./scripts/auto-maintenance.sh"

# DEV commands
echo -e "${BLUE}🛠️  Creando comandos dev/...${RESET}"
create_wip_command "dev" "test" "Ejecutar tests" ""
create_wip_command "dev" "validate" "Validar todo el sistema" ""

echo ""
echo -e "${GREEN}✅ Estructura de comandos creada exitosamente${RESET}"
echo ""
echo -e "${BLUE}📊 Resumen:${RESET}"
echo "   - show:     5 comandos (1 implementado ✅, 4 WIP 🚧)"
echo "   - deploy:   7 comandos (todos WIP 🚧)"
echo "   - config:   4 comandos (todos WIP 🚧)"
echo "   - backup:   4 comandos (todos WIP 🚧)"
echo "   - setup:    7 comandos (todos WIP 🚧)"
echo "   - maintain: 4 comandos (todos WIP 🚧)"
echo "   - dev:      2 comandos (todos WIP 🚧)"
echo ""
echo -e "${BLUE}🎯 Total: 33 comandos (1 implementado, 32 WIP)${RESET}"
echo ""

