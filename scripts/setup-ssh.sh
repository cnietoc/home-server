#!/usr/bin/env bash
set -euo pipefail

# Cargar configuración común
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common/env-loader.sh"
load_common_config

# === ARGUMENTOS: usar configuración o parámetros ===
if [[ $# -gt 0 ]]; then
    GITHUB_USERS=("$@")
    log "Usando usuarios de GitHub desde argumentos: ${GITHUB_USERS[*]}"
elif [[ -n "${GITHUB_SSH_USERS:-}" ]]; then
    read -ra GITHUB_USERS <<< "$GITHUB_SSH_USERS"
    log "Usando usuarios de GitHub desde configuración: ${GITHUB_USERS[*]}"
else
    echo "❌ Especifica usuarios de GitHub:"
    echo "   - Como argumentos: $0 <github_user1> [github_user2 ...]"
    echo "   - O configurando GITHUB_SSH_USERS en config/private/common.env"
    exit 1
fi

LOCAL_USER="$(whoami)"       # Usuario local que ejecuta el script
SSH_DIR="$HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
TMP_KEYS="/tmp/github_keys_tmp_$$"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

cleanup() {
    rm -f "$TMP_KEYS"
}
trap cleanup EXIT

# === INSTALAR SERVIDOR SSH SI NO ESTÁ INSTALADO ===
if ! dpkg -s openssh-server >/dev/null 2>&1; then
    log "openssh-server no está instalado. Instalando..."
    sudo apt update && sudo apt install -y openssh-server
    log "✅ openssh-server instalado."
else
    log "openssh-server ya está instalado."
fi

# === CREAR DIRECTORIO .ssh ===
log "Creando directorio $SSH_DIR si no existe..."
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$LOCAL_USER":"$LOCAL_USER" "$SSH_DIR"

# === DESCARGAR Y UNIR CLAVES PÚBLICAS DE GITHUB ===
true > "$TMP_KEYS"
ACTIVE_USERS=()  # Usuarios que aportan claves válidas

for GH_USER in "${GITHUB_USERS[@]}"; do
    log "Descargando claves de GitHub: $GH_USER"
    if curl -fsSL "https://github.com/$GH_USER.keys" >> "$TMP_KEYS"; then
        if [[ -s "$TMP_KEYS" ]]; then
            echo "" >> "$TMP_KEYS"
            ACTIVE_USERS+=("$GH_USER")
        fi
    else
        echo "⚠️ No se pudieron obtener claves de $GH_USER, se salta."
    fi
done

if [[ ${#ACTIVE_USERS[@]} -eq 0 ]]; then
    echo "❌ No se descargó ninguna clave pública válida, abortando."
    rm -f "$TMP_KEYS"
    exit 1
fi

# === ELIMINAR duplicados y actualizar authorized_keys ===
sort -u "$TMP_KEYS" -o "$TMP_KEYS"

if [[ ! -f "$AUTHORIZED_KEYS" ]] || ! cmp -s "$TMP_KEYS" "$AUTHORIZED_KEYS"; then
    cp "$TMP_KEYS" "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    chown "$LOCAL_USER":"$LOCAL_USER" "$AUTHORIZED_KEYS"
    log "✅ authorized_keys actualizado con claves válidas."
else
    log "Las claves no han cambiado, no se actualiza authorized_keys."
fi
rm -f "$TMP_KEYS"

# === CONFIGURACIÓN DE SSHD IDÓMPOTENTE ===
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.backup"

if [[ ! -f "$BACKUP_CONFIG" ]]; then
    log "Haciendo copia de seguridad de $SSHD_CONFIG..."
    sudo cp "$SSHD_CONFIG" "$BACKUP_CONFIG"
fi

log "Configurando SSH para aceptar solo autenticación por clave pública..."

ensure_sshd_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    if sudo grep -qE "^\s*${key}\b" "$file"; then
        sudo sed -ri "s|^\s*${key}\b.*|${key} ${value}|" "$file"
    else
        echo "${key} ${value}" | sudo tee -a "$file" >/dev/null
    fi
}

# Ajustes principales
ensure_sshd_config "PasswordAuthentication" "no" "$SSHD_CONFIG"
ensure_sshd_config "ChallengeResponseAuthentication" "no" "$SSHD_CONFIG"
ensure_sshd_config "UsePAM" "no" "$SSHD_CONFIG"
ensure_sshd_config "PermitRootLogin" "no" "$SSHD_CONFIG"
ensure_sshd_config "PubkeyAuthentication" "yes" "$SSHD_CONFIG"
ensure_sshd_config "AuthorizedKeysFile" ".ssh/authorized_keys" "$SSHD_CONFIG"
ensure_sshd_config "PermitEmptyPasswords" "no" "$SSHD_CONFIG"

# Validar configuración antes de aplicar
TEMP_CONFIG="/tmp/sshd_config_test_$$"
sudo cp "$SSHD_CONFIG" "$TEMP_CONFIG"
if sudo sshd -t -f "$TEMP_CONFIG"; then
    log "✅ Configuración SSH validada correctamente."
    sudo rm -f "$TEMP_CONFIG"
else
    log "❌ Error en configuración SSH, restaurando backup..."
    sudo cp "$BACKUP_CONFIG" "$SSHD_CONFIG"
    sudo rm -f "$TEMP_CONFIG"
    exit 1
fi

# === REINICIAR SSH ===
log "Recargando servicio SSH..."
sudo systemctl restart ssh || sudo service ssh restart

# === VERIFICAR ESTADO ===
if sudo systemctl is-active ssh >/dev/null 2>&1; then
    log "✅ SSH está activo y funcionando."
else
    log "⚠️ SSH puede no estar funcionando correctamente."
fi

# === RESUMEN FINAL ===
log "✅ Configuración completada."
log "Usuario local que accede por SSH: $LOCAL_USER"
log "Usuarios de GitHub con claves válidas en authorized_keys: ${ACTIVE_USERS[*]}"
log "Solo autenticación por clave pública habilitada."
