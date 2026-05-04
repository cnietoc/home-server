#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"
}

# === ARGUMENTS ===
if [[ $# -gt 0 ]]; then
    GITHUB_USERS=("$@")
    log "Using GitHub users from arguments: ${GITHUB_USERS[*]}"
else
    error "Specify GitHub users:"
    info "As arguments: $0 <github_user1> [github_user2 ...]"
    exit 1
fi

LOCAL_USER="$(whoami)"       # Local user running the script
SSH_DIR="$HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
TMP_KEYS="/tmp/github_keys_tmp_$$"

cleanup() {
    rm -f "$TMP_KEYS"
}
trap cleanup EXIT

# === INSTALL SSH SERVER IF NOT INSTALLED ===
if ! dpkg -s openssh-server >/dev/null 2>&1; then
    log "openssh-server is not installed. Installing..."
    sudo apt update && sudo apt install -y openssh-server
    log "✅ openssh-server installed."
else
    log "openssh-server is already installed."
fi

# === CREATE .ssh DIRECTORY ===
log "Creating directory $SSH_DIR if it does not exist..."
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$LOCAL_USER":"$LOCAL_USER" "$SSH_DIR"

# === DOWNLOAD AND MERGE GITHUB PUBLIC KEYS ===
true > "$TMP_KEYS"
ACTIVE_USERS=()  # Users that provide valid keys

for GH_USER in "${GITHUB_USERS[@]}"; do
    log "Downloading GitHub keys for: $GH_USER"
    if curl -fsSL "https://github.com/$GH_USER.keys" >> "$TMP_KEYS"; then
        if [[ -s "$TMP_KEYS" ]]; then
            echo "" >> "$TMP_KEYS"
            ACTIVE_USERS+=("$GH_USER")
        fi
    else
        warn "Could not fetch keys for $GH_USER, skipping."
    fi
done

if [[ ${#ACTIVE_USERS[@]} -eq 0 ]]; then
    error "No valid public keys downloaded, aborting."
    rm -f "$TMP_KEYS"
    exit 1
fi

# === DEDUPLICATE AND UPDATE authorized_keys ===
sort -u "$TMP_KEYS" -o "$TMP_KEYS"

if [[ ! -f "$AUTHORIZED_KEYS" ]] || ! cmp -s "$TMP_KEYS" "$AUTHORIZED_KEYS"; then
    cp "$TMP_KEYS" "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    chown "$LOCAL_USER":"$LOCAL_USER" "$AUTHORIZED_KEYS"
    log "✅ authorized_keys updated with valid keys."
else
    log "Keys have not changed, authorized_keys not updated."
fi
rm -f "$TMP_KEYS"

# === IDEMPOTENT SSHD CONFIGURATION ===
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.backup"

if [[ ! -f "$BACKUP_CONFIG" ]]; then
    log "Backing up $SSHD_CONFIG..."
    sudo cp "$SSHD_CONFIG" "$BACKUP_CONFIG"
fi

log "Configuring SSH to accept only public key authentication..."

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

ensure_sshd_config "PasswordAuthentication" "no" "$SSHD_CONFIG"
ensure_sshd_config "ChallengeResponseAuthentication" "no" "$SSHD_CONFIG"
ensure_sshd_config "UsePAM" "no" "$SSHD_CONFIG"
ensure_sshd_config "PermitRootLogin" "no" "$SSHD_CONFIG"
ensure_sshd_config "PubkeyAuthentication" "yes" "$SSHD_CONFIG"
ensure_sshd_config "AuthorizedKeysFile" ".ssh/authorized_keys" "$SSHD_CONFIG"
ensure_sshd_config "PermitEmptyPasswords" "no" "$SSHD_CONFIG"

# Validate configuration before applying
TEMP_CONFIG="/tmp/sshd_config_test_$$"
sudo cp "$SSHD_CONFIG" "$TEMP_CONFIG"
if sudo sshd -t -f "$TEMP_CONFIG"; then
    log "✅ SSH configuration validated."
    sudo rm -f "$TEMP_CONFIG"
else
    error "SSH configuration error, restoring backup..."
    sudo cp "$BACKUP_CONFIG" "$SSHD_CONFIG"
    sudo rm -f "$TEMP_CONFIG"
    exit 1
fi

# === RESTART SSH ===
log "Restarting SSH service..."
sudo systemctl restart ssh || sudo service ssh restart

# === VERIFY STATUS ===
if sudo systemctl is-active ssh >/dev/null 2>&1; then
    log "✅ SSH is active and running."
else
    warn "SSH may not be functioning correctly."
fi

# === FINAL SUMMARY ===
log "✅ Configuration complete."
log "Local user with SSH access: $LOCAL_USER"
log "GitHub users with valid keys in authorized_keys: ${ACTIVE_USERS[*]}"
log "Only public key authentication is enabled."
