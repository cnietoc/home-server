#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ONEDRIVE SYNC MANAGER - Setup and management of OneDrive sync via rclone and systemd
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RCLONE_CONFIG_DIR="${HOME}/.config/rclone"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_DIR}/rclone.conf"
REMOTE_NAME="onedrive"
SELECTED_FOLDER=""
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
BACKUP_SERVICE="home-server-backup-sync"
CONFIG_SERVICE="home-server-config-sync"

# Logging
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"; }
info() { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $*"; }
header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $* ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}
prompt() { echo -e "${MAGENTA}➜${NC} $*"; }

# Verify the system is compatible (Ubuntu/Debian/Linux)
check_system() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine the operating system"
        exit 1
    fi

    . /etc/os-release
    log "✅ System detected: $PRETTY_NAME"
}

# Check and install rclone if not installed
install_rclone() {
    if command -v rclone >/dev/null 2>&1; then
        local version=$(rclone version 2>&1 | head -n1)
        info "rclone is already installed: $version"
        return 0
    fi

    header "Installing rclone"

    log "Downloading and installing rclone..."
    curl https://rclone.org/install.sh | sudo bash

    if command -v rclone >/dev/null 2>&1; then
        success "rclone installed successfully"
    else
        error "Failed to install rclone"
        exit 1
    fi
}

# Check if an OneDrive remote already exists
check_existing_remote() {
    if [[ -f "$RCLONE_CONFIG_FILE" ]] && rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
        return 0
    else
        return 1
    fi
}

# Configure OneDrive remote
configure_onedrive_remote() {
    header "OneDrive configuration with rclone"

    # Create config directory if it doesn't exist
    mkdir -p "$RCLONE_CONFIG_DIR"

    if check_existing_remote; then
        warn "A remote named '$REMOTE_NAME' already exists"
        prompt "Reconfigure it? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Using existing configuration"
            return 0
        fi

        log "Removing existing configuration..."
        rclone config delete "$REMOTE_NAME" 2>/dev/null || true
    fi

    echo ""
    log "🔧 Starting interactive OneDrive configuration..."
    echo ""
    info "INSTRUCTIONS:"
    echo -e "  1. Select 'n' to create a new remote"
    echo -e "  2. Remote name: ${GREEN}${REMOTE_NAME}${NC}"
    echo -e "  3. Storage type: find '${GREEN}onedrive${NC}' or its number"
    echo -e "  4. Client ID and Secret: leave ${GREEN}empty${NC} (press Enter)"
    echo -e "  5. Region: select '${GREEN}1${NC}' (Microsoft Cloud Global)"
    echo -e "  6. Advanced config: ${GREEN}No${NC}"
    echo -e "  7. Auto auth: ${GREEN}Yes${NC}"
    echo -e "  8. A browser will open to authorize access"
    echo -e "  9. Config type: ${GREEN}1${NC} (OneDrive Personal or Business)"
    echo -e "  10. Confirm selection and save"
    echo ""
    warn "⚠️  Make sure you have a browser available for authorization"
    echo ""
    prompt "Press Enter to continue..."
    read -r

    # Run interactive configuration
    rclone config

    # Verify the remote was created
    if check_existing_remote; then
        success "Remote '$REMOTE_NAME' configured successfully"
        return 0
    else
        error "Failed to configure remote '$REMOTE_NAME'"
        exit 1
    fi
}

# Interactively list OneDrive folders
list_onedrive_folders() {
    local current_path="$1"
    local display_path="${current_path:-/}"

    echo ""
    header "Browsing OneDrive: $display_path"

    log "Fetching folder list..."

    # Get folders
    local folders=()
    while IFS= read -r line; do
        folders+=("$line")
    done < <(rclone lsd "${REMOTE_NAME}:${current_path}" 2>/dev/null | awk '{$1=$2=$3=$4=""; print substr($0,5)}' | sed 's/^[[:space:]]*//')

    if [[ ${#folders[@]} -eq 0 ]]; then
        warn "No subfolders found at this location"
    else
        echo ""
        info "Available folders:"
        for i in "${!folders[@]}"; do
            echo -e "  ${CYAN}$((i+1)).${NC} ${folders[$i]}"
        done
    fi

    echo ""
    echo -e "Options:"
    echo -e "  ${GREEN}[number]${NC} - Enter a folder"
    echo -e "  ${GREEN}..${NC}       - Go back"
    echo -e "  ${GREEN}.${NC}        - Use current folder"
    echo -e "  ${GREEN}q${NC}        - Cancel and exit"
    echo ""
    prompt "Selection: "
    read -r selection

    case "$selection" in
        q|Q)
            error "Configuration cancelled by user"
            exit 0
            ;;
        .)
            SELECTED_FOLDER="$current_path"
            return 0
            ;;
        ..)
            if [[ -n "$current_path" ]]; then
                local parent_path=$(dirname "$current_path")
                [[ "$parent_path" == "." ]] && parent_path=""
                list_onedrive_folders "$parent_path"
            else
                warn "Already at root"
                list_onedrive_folders "$current_path"
            fi
            ;;
        *)
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#folders[@]} ]]; then
                local selected_folder="${folders[$((selection-1))]}"
                local new_path="${current_path:+$current_path/}${selected_folder}"
                list_onedrive_folders "$new_path"
            else
                error "Invalid selection"
                list_onedrive_folders "$current_path"
            fi
            ;;
    esac
}

# Interactive folder selection
select_onedrive_folder() {
    header "Select working folder in OneDrive"

    echo ""
    info "We will select the folder where backups will be synced"
    echo ""

    # Verify connectivity
    log "Verifying connection to OneDrive..."
    if ! rclone lsd "${REMOTE_NAME}:" >/dev/null 2>&1; then
        error "Could not connect to OneDrive. Check your configuration."
        exit 1
    fi
    success "OneDrive connection verified"

    # Start navigation
    list_onedrive_folders ""

    echo ""
    success "Selected folder: ${CYAN}${SELECTED_FOLDER:-/}${NC}"

    # Create folder structure in OneDrive if it doesn't exist
    log "Verifying folder structure in OneDrive..."

    local base_path="${SELECTED_FOLDER:+$SELECTED_FOLDER/}"
    rclone mkdir "${REMOTE_NAME}:${base_path}/backups" 2>/dev/null || true
    rclone mkdir "${REMOTE_NAME}:${base_path}/config" 2>/dev/null || true

    success "Folder structure created in OneDrive"

    # Save the selected path
    echo "$base_path" > "${PROJECT_ROOT}/.onedrive-path"
}

# Create systemd service for backup sync
create_backup_sync_service() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    header "Creating backup sync service"

    mkdir -p "$SYSTEMD_USER_DIR"

    # Create service file
    cat > "${SYSTEMD_USER_DIR}/home-server-backup-sync.service" <<EOF
[Unit]
Description=Home Server - Backup Sync to OneDrive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# Prevent concurrent runs
ExecStartPre=/bin/bash -c 'if [ -f ${PROJECT_ROOT}/logs/backup-sync.lock ]; then echo "Sync already in progress"; exit 1; fi'
ExecStartPre=/bin/bash -c 'echo $$ > ${PROJECT_ROOT}/logs/backup-sync.lock'
ExecStart=/usr/bin/rclone sync \\
    ${PROJECT_ROOT}/backups \\
    ${REMOTE_NAME}:${onedrive_path}backups \\
    --delete-during \\
    --log-file=${PROJECT_ROOT}/logs/rclone-backup-sync.log \\
    --log-level INFO \\
    --exclude .gitignore \\
    --transfers 8 \\
    --checkers 16 \\
    --buffer-size 32M \\
    --use-mmap \\
    --fast-list \\
    --contimeout 60s \\
    --timeout 0 \\
    --retries 5 \\
    --low-level-retries 20 \\
    --stats 1m \\
    --stats-one-line
ExecStopPost=/bin/bash -c 'rm -f ${PROJECT_ROOT}/logs/backup-sync.lock'

[Install]
WantedBy=default.target
EOF

    # Create timer file
    cat > "${SYSTEMD_USER_DIR}/home-server-backup-sync.timer" <<EOF
[Unit]
Description=Timer for daily backup sync to OneDrive at 3 AM
Requires=home-server-backup-sync.service

[Timer]
OnCalendar=*-*-* 03:00:00
OnBootSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    success "Backup sync service created"
}

# Create systemd service for config sync
create_config_sync_service() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    header "Creating config sync service"

    mkdir -p "$SYSTEMD_USER_DIR"

    # Create service file
    cat > "${SYSTEMD_USER_DIR}/home-server-config-sync.service" <<EOF
[Unit]
Description=Home Server - config.toml Sync to OneDrive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
# Prevent concurrent runs
ExecStartPre=/bin/bash -c 'if [ -f ${PROJECT_ROOT}/logs/config-sync.lock ]; then echo "Sync already in progress"; exit 1; fi'
ExecStartPre=/bin/bash -c 'echo $$ > ${PROJECT_ROOT}/logs/config-sync.lock'
ExecStart=/usr/bin/rclone copyto \\
    ${PROJECT_ROOT}/config.toml \\
    ${REMOTE_NAME}:${onedrive_path}config/config.toml \\
    --log-file=${PROJECT_ROOT}/logs/rclone-config-sync.log \\
    --log-level INFO \\
    --contimeout 60s \\
    --timeout 300s \\
    --retries 3
ExecStopPost=/bin/bash -c 'rm -f ${PROJECT_ROOT}/logs/config-sync.lock'

[Install]
WantedBy=default.target
EOF

    # Create timer file
    cat > "${SYSTEMD_USER_DIR}/home-server-config-sync.timer" <<EOF
[Unit]
Description=Timer for hourly config.toml sync to OneDrive
Requires=home-server-config-sync.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    success "Config sync service created"
}

# Enable and start systemd services
enable_systemd_services() {
    header "Enabling systemd services"

    # Reload systemd
    log "Reloading systemd configuration..."
    systemctl --user daemon-reload

    # Enable and start timers
    log "Enabling backup sync timer..."
    systemctl --user enable home-server-backup-sync.timer
    systemctl --user start home-server-backup-sync.timer

    log "Enabling config sync timer..."
    systemctl --user enable home-server-config-sync.timer
    systemctl --user start home-server-config-sync.timer

    # Enable lingering so services run without an active session
    if loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=no"; then
        log "Enabling lingering for user $(whoami)..."
        sudo loginctl enable-linger "$(whoami)"
    fi

    success "systemd services enabled and running"
}

# Run initial sync
run_initial_sync() {
    header "Running initial sync"

    warn "This may take several minutes depending on the size of your backups..."
    echo ""

    # Sync backups
    log "Syncing backups..."
    systemctl --user start home-server-backup-sync.service

    # Wait for it to finish
    while systemctl --user is-active --quiet home-server-backup-sync.service; do
        sleep 2
    done

    if systemctl --user is-failed --quiet home-server-backup-sync.service; then
        warn "Backup sync encountered problems. Check the logs."
    else
        success "Backups synced"
    fi

    # Sync config
    log "Syncing config.toml..."
    systemctl --user start home-server-config-sync.service

    # Wait for it to finish
    while systemctl --user is-active --quiet home-server-config-sync.service; do
        sleep 1
    done

    if systemctl --user is-failed --quiet home-server-config-sync.service; then
        warn "Config sync encountered problems. Check the logs."
    else
        success "Config synced"
    fi
}

# Show final information
show_final_info() {
    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")

    echo ""
    header "🎉 Setup completed successfully"
    echo ""

    success "Configuration summary:"
    echo ""
    echo -e "  ${CYAN}rclone remote:${NC}         ${REMOTE_NAME}"
    echo -e "  ${CYAN}OneDrive folder:${NC}       ${onedrive_path}"
    echo -e "  ${CYAN}Local backups folder:${NC}  ${PROJECT_ROOT}/backups"
    echo -e "  ${CYAN}config.toml file:${NC}      ${PROJECT_ROOT}/config.toml"
    echo ""

    info "Configured services:"
    echo -e "  ${GREEN}✓${NC} home-server-backup-sync  - Syncs backups daily at 3 AM"
    echo -e "  ${GREEN}✓${NC} home-server-config-sync  - Syncs config.toml every hour"
    echo ""

    info "Special behavior:"
    echo -e "  ${GREEN}✓${NC} If the PC is off at 3 AM, the backup runs on next boot"
    echo -e "  ${GREEN}✓${NC} Files deleted locally are also deleted from OneDrive"
    echo -e "  ${GREEN}✓${NC} OneDrive keeps a recycle bin (30 days of recovery)"
    echo ""

    info "Useful commands:"
    echo ""
    echo -e "  ${CYAN}# Check service status${NC}"
    echo "  systemctl --user status home-server-backup-sync.timer"
    echo "  systemctl --user status home-server-config-sync.timer"
    echo ""
    echo -e "  ${CYAN}# View sync logs${NC}"
    echo "  journalctl --user -u home-server-backup-sync.service -f"
    echo "  journalctl --user -u home-server-config-sync.service -f"
    echo ""
    echo -e "  ${CYAN}# Force immediate sync${NC}"
    echo "  systemctl --user start home-server-backup-sync.service"
    echo "  systemctl --user start home-server-config-sync.service"
    echo ""
    echo -e "  ${CYAN}# View rclone log files${NC}"
    echo "  cat ${PROJECT_ROOT}/logs/rclone-backup-sync.log"
    echo "  cat ${PROJECT_ROOT}/logs/rclone-config-sync.log"
    echo ""
    echo -e "  ${CYAN}# Disable sync${NC}"
    echo "  systemctl --user stop home-server-backup-sync.timer"
    echo "  systemctl --user disable home-server-backup-sync.timer"
    echo ""

    success "All set! Your backups and config will sync automatically with OneDrive."
}

# ============================================================================
# MANAGEMENT FUNCTIONS
# ============================================================================

# Show status
show_status() {
    header "OneDrive Sync Status"
    echo ""

    local backup_timer_status=$(systemctl --user is-active ${BACKUP_SERVICE}.timer 2>/dev/null || echo "inactive")
    local config_timer_status=$(systemctl --user is-active ${CONFIG_SERVICE}.timer 2>/dev/null || echo "inactive")

    echo -e "${BLUE}Services:${NC}"
    if [[ "$backup_timer_status" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} Backup sync: ${GREEN}active${NC}"
    else
        echo -e "  ${RED}●${NC} Backup sync: ${RED}inactive${NC}"
    fi

    if [[ "$config_timer_status" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} Config sync: ${GREEN}active${NC}"
    else
        echo -e "  ${RED}●${NC} Config sync: ${RED}inactive${NC}"
    fi

    echo ""
    echo -e "${BLUE}Next runs:${NC}"
    systemctl --user list-timers ${BACKUP_SERVICE}.timer ${CONFIG_SERVICE}.timer 2>/dev/null | grep -E "NEXT|home-server" || echo "  Not scheduled"

    if [[ -f "${PROJECT_ROOT}/.onedrive-path" ]]; then
        local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")
        echo ""
        echo -e "${BLUE}Configuration:${NC}"
        echo "  OneDrive path: onedrive:${onedrive_path}"
        echo "  Local folder:  ${PROJECT_ROOT}/backups"
    fi
}

# Sync now
sync_now() {
    local service=$1
    local name=$2

    log "Syncing ${name}..."
    systemctl --user start ${service}.service

    local timeout=300
    local elapsed=0

    while systemctl --user is-active --quiet ${service}.service; do
        sleep 2
        elapsed=$((elapsed + 2))
        [[ $elapsed -ge $timeout ]] && { warn "Timeout"; return 1; }
        [[ $((elapsed % 10)) -eq 0 ]] && echo -n "."
    done

    echo ""

    if systemctl --user is-failed --quiet ${service}.service; then
        error "${name} sync failed"
        journalctl --user -u ${service}.service -n 20 --no-pager
        return 1
    else
        success "${name} sync complete"
        return 0
    fi
}

# Show logs
show_logs() {
    local service=$1
    local lines=${2:-50}

    header "Logs for ${service}"
    journalctl --user -u ${service}.service -n ${lines} --no-pager
}

# Follow logs live
follow_logs() {
    local service=$1
    header "Live logs for ${service} (Ctrl+C to exit)"
    journalctl --user -u ${service}.service -f
}

# Enable/disable services
toggle_services() {
    local action=$1

    log "${action^} services..."
    systemctl --user ${action} ${BACKUP_SERVICE}.timer
    systemctl --user ${action} ${CONFIG_SERVICE}.timer

    if [[ "$action" == "enable" ]]; then
        systemctl --user start ${BACKUP_SERVICE}.timer
        systemctl --user start ${CONFIG_SERVICE}.timer
    fi

    success "Services ${action}d"
}

# Health check
check_health() {
    header "Health check"
    echo ""

    local errors=0

    command -v rclone >/dev/null 2>&1 && success "rclone installed" || { error "rclone not installed"; ((errors++)); }
    rclone listremotes 2>/dev/null | grep -q "^onedrive:" && success "OneDrive configured" || { error "OneDrive not configured"; ((errors++)); }
    rclone about onedrive: >/dev/null 2>&1 && success "Connectivity OK" || { error "No connection to OneDrive"; ((errors++)); }
    systemctl --user list-unit-files | grep -q ${BACKUP_SERVICE} && success "Services installed" || { error "Services not found"; ((errors++)); }
    [[ -d "${PROJECT_ROOT}/backups" ]] && success "Backups folder OK" || warn "Backups folder not found"
    [[ -f "${PROJECT_ROOT}/config.toml" ]] && success "config.toml OK" || warn "config.toml not found"

    echo ""
    [[ $errors -eq 0 ]] && success "✅ System OK" || error "❌ ${errors} error(s)"
    return $errors
}

# List files in OneDrive
list_onedrive() {
    [[ ! -f "${PROJECT_ROOT}/.onedrive-path" ]] && { error "OneDrive not configured"; exit 1; }

    local onedrive_path=$(cat "${PROJECT_ROOT}/.onedrive-path")
    header "Contents in OneDrive: ${onedrive_path}"

    log "Backups:"
    rclone ls onedrive:${onedrive_path}backups --max-depth 1 2>/dev/null || echo "  (empty)"

    echo ""
    log "Config:"
    rclone ls onedrive:${onedrive_path}config 2>/dev/null || echo "  (empty)"
}

# Remove sync completely
remove_sync() {
    header "Removing OneDrive sync"
    echo ""

    warn "This will remove:"
    echo -e "  ${RED}●${NC} systemd services (timers and services)"
    echo -e "  ${RED}●${NC} OneDrive path config file (.onedrive-path)"
    echo -e "  ${RED}●${NC} Lock files"
    echo ""
    echo -e "  Files in OneDrive and rclone.conf ${CYAN}are kept${NC}"
    echo ""

    prompt "Continue? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Operation cancelled"
        return 0
    fi

    log "Stopping services..."
    systemctl --user stop ${BACKUP_SERVICE}.timer 2>/dev/null || true
    systemctl --user stop ${CONFIG_SERVICE}.timer 2>/dev/null || true
    systemctl --user stop ${BACKUP_SERVICE}.service 2>/dev/null || true
    systemctl --user stop ${CONFIG_SERVICE}.service 2>/dev/null || true

    log "Disabling services..."
    systemctl --user disable ${BACKUP_SERVICE}.timer 2>/dev/null || true
    systemctl --user disable ${CONFIG_SERVICE}.timer 2>/dev/null || true
    systemctl --user disable ${BACKUP_SERVICE}.service 2>/dev/null || true
    systemctl --user disable ${CONFIG_SERVICE}.service 2>/dev/null || true

    log "Removing service files..."
    rm -f "${SYSTEMD_USER_DIR}/${BACKUP_SERVICE}.service" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${BACKUP_SERVICE}.timer" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${CONFIG_SERVICE}.service" 2>/dev/null || true
    rm -f "${SYSTEMD_USER_DIR}/${CONFIG_SERVICE}.timer" 2>/dev/null || true

    log "Reloading systemd..."
    systemctl --user daemon-reload

    log "Removing path config file..."
    rm -f "${PROJECT_ROOT}/.onedrive-path" 2>/dev/null || true

    log "Removing lock files..."
    rm -f "${PROJECT_ROOT}/logs/backup-sync.lock" 2>/dev/null || true
    rm -f "${PROJECT_ROOT}/logs/config-sync.lock" 2>/dev/null || true

    echo ""
    success "✅ Sync removed completely"
    echo ""
    info "To reinstall sync, run:"
    echo -e "  ${CYAN}$0 setup${NC}"
    echo ""
    info "To reconfigure from scratch:"
    echo -e "  ${CYAN}$0 setup --force${NC}"
}

# Help
show_help() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "  OneDrive Sync Manager - All-in-one setup and management"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}SETUP (first time):${NC}"
    echo -e "  $0 setup              Full interactive setup"
    echo -e "  $0 setup --force      Reconfigure from scratch"
    echo ""
    echo -e "${GREEN}MANAGEMENT:${NC}"
    echo -e "  $0 status             Sync status"
    echo -e "  $0 sync               Sync everything now"
    echo -e "  $0 sync-backup        Sync backups only"
    echo -e "  $0 sync-config        Sync config.toml only"
    echo ""
    echo -e "  $0 logs [N]           View last N backup logs"
    echo -e "  $0 logs-config [N]    View last N config logs"
    echo -e "  $0 follow             Follow backup logs live"
    echo -e "  $0 follow-config      Follow config logs live"
    echo ""
    echo -e "  $0 enable             Enable automatic sync"
    echo -e "  $0 disable            Disable automatic sync"
    echo -e "  $0 restart            Restart services"
    echo ""
    echo -e "  $0 list               List files in OneDrive"
    echo -e "  $0 health             Check system health"
    echo ""
    echo -e "${RED}UNINSTALL:${NC}"
    echo -e "  $0 remove             Remove sync completely"
    echo ""
    echo -e "${GREEN}EXAMPLES:${NC}"
    echo -e "  $0 setup              # First-time setup"
    echo -e "  $0 status             # Check status"
    echo -e "  $0 sync               # Sync now"
    echo -e "  $0 logs 100           # View last 100 log lines"
    echo -e "  $0 follow             # Follow logs live"
    echo -e "  $0 remove             # Remove sync"
    echo ""
    echo -e "${GREEN}LOG FILES:${NC}"
    echo -e "  ${PROJECT_ROOT}/logs/rclone-backup-sync.log"
    echo -e "  ${PROJECT_ROOT}/logs/rclone-config-sync.log"
    echo ""
    echo -e "${GREEN}SYSTEMD COMMANDS:${NC}"
    echo -e "  systemctl --user status ${BACKUP_SERVICE}.timer"
    echo -e "  journalctl --user -u ${BACKUP_SERVICE}.service -f"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

# Full setup
run_setup() {
    local reconfigure=${1:-false}

    clear
    header "🚀 OneDrive Sync Manager - Setup"
    echo ""

    check_system
    install_rclone

    if $reconfigure || ! check_existing_remote; then
        configure_onedrive_remote
    else
        info "Using existing OneDrive configuration"
    fi

    select_onedrive_folder
    create_backup_sync_service
    create_config_sync_service
    enable_systemd_services

    echo ""
    prompt "Run initial sync now? (Y/n): "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        run_initial_sync
    fi

    show_final_info
}

# Command dispatcher
main() {
    # Handle setup --force
    if [[ "${1:-}" == "setup" && "${2:-}" == "--force" ]]; then
        run_setup true
        return
    fi

    case "${1:-help}" in
        setup)
            run_setup false
            ;;
        status|st)
            show_status
            ;;
        sync|sync-all)
            sync_now "$BACKUP_SERVICE" "backups"
            echo ""
            sync_now "$CONFIG_SERVICE" "config"
            ;;
        sync-backup|sync-backups)
            sync_now "$BACKUP_SERVICE" "backups"
            ;;
        sync-config)
            sync_now "$CONFIG_SERVICE" "config"
            ;;
        logs)
            show_logs "$BACKUP_SERVICE" "${2:-50}"
            ;;
        logs-config)
            show_logs "$CONFIG_SERVICE" "${2:-50}"
            ;;
        follow|tail)
            follow_logs "$BACKUP_SERVICE"
            ;;
        follow-config|tail-config)
            follow_logs "$CONFIG_SERVICE"
            ;;
        enable|start)
            toggle_services "enable"
            ;;
        disable|stop)
            toggle_services "disable"
            ;;
        restart|reload)
            log "Reloading services..."
            systemctl --user daemon-reload
            systemctl --user restart ${BACKUP_SERVICE}.timer
            systemctl --user restart ${CONFIG_SERVICE}.timer
            success "Services restarted"
            ;;
        list|ls)
            list_onedrive
            ;;
        health|check)
            check_health
            ;;
        remove|uninstall)
            remove_sync
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Handle interrupt signals
trap 'error "Interrupted"; exit 130' INT TERM

# Run
main "$@"
