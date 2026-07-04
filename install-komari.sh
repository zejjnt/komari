#!/bin/bash

# Color definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # Reset prompt decoration and color

# Logging functions
log_info() {
    echo -e "$1"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

log_step() {
    echo -e "${YELLOW}$1${NC}"
}


# Global variables
INSTALL_DIR="/opt/komari"
DATA_DIR="/opt/komari"
SERVICE_NAME="komari"
BINARY_PATH="$INSTALL_DIR/komari"
DEFAULT_PORT="25774"
LISTEN_PORT=""

# Show banner
show_banner() {
    clear
    echo "=============================================================="
    echo "         Komari monitoring system installer (eng WIP)"
    echo "           https://github.com/zejjnt/komari"
    echo "            Eng: https://github.com/zejjnt/komari"
    echo "=============================================================="
    echo
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script needs superuser permissions to run!"
        exit 1
    fi
}

# Check for systemd
check_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# Detect system architecture
detect_arch() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        i386|i686)
            echo "386"
            ;;
        riscv64)
            echo "riscv64"
            ;;
        *)
            log_error "Unsupported system architecture $arch"
            exit 1
            ;;
    esac
}

# Check if Komari is already installed
is_installed() {
    if [ -f "$BINARY_PATH" ]; then
        return 0 # 0 means true in bash exit codes
    else
        return 1 # 1 means false
    fi
}

# Install dependencies
install_dependencies() {
    log_step "Checking and installing dependencies..."

    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt >/dev/null 2>&1; then
            log_info "Installing dependencies using apt..."
            apt update
            apt install -y curl
        elif command -v yum >/dev/null 2>&1; then
            log_info "Installing dependencies using yum..."
            yum install -y curl
        elif command -v apk >/dev/null 2>&1; then
            log_info "Installing dependencies using apk..."
            apk add curl
        else
            log_error "Could not find any supported package manager (apt/yum/apk)"
            exit 1
        fi
    fi
}

# Binary installation
install_binary() {
    log_step "Installing Komari binary..."

    if is_installed; then
        log_info "Komari has been installed."
        return
    fi


    # Listening port, allowed port range 1-65535
    while true; do
        read -rp "Select server listen port: [ $DEFAULT_PORT ]: " input_port
        if [[ -z "$input_port" ]]; then
            LISTEN_PORT="$DEFAULT_PORT"
            break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && (( input_port >= 1 && input_port <= 65535 )); then
            LISTEN_PORT="$input_port"
            break
        else
            log_error "Invalid port number. Enter a number between 1 and 65535."
        fi
    done

    install_dependencies

    local arch
    arch=$(detect_arch)
    log_info "Detected architecture $arch"

    log_step "Creating install directory $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    log_step "Creating data directory $DATA_DIR"
    mkdir -p "$DATA_DIR"

    local file_name="komari-linux-${arch}"
    local download_url="https://github.com/zejjnt/komari/releases/latest/download/${file_name}"

    log_step "Downloading latest Komari binary..."
    log_info "URL: $download_url"

    if ! curl -L -o "$BINARY_PATH" "$download_url"; then
        log_error "Download failed!"
        return 1
    fi

    chmod +x "$BINARY_PATH"
    log_success "Komari has been successfully installed at $BINARY_PATH"

    if ! check_systemd; then
        log_step "Warning: systemd cannot be found! Could not create a service for Komari."
        log_step "Launch Komari manually:"
        log_step "    $BINARY_PATH server -l 0.0.0.0:$LISTEN_PORT"
        echo
        log_success "Installation completed successfully!"
        return
    fi

    create_systemd_service "$LISTEN_PORT"

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}.service
    systemctl start ${SERVICE_NAME}.service

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log_success "The Komari service has been started."
        
        log_step "Randomizing initial password..."
        sleep 5
        local password
        password=$(journalctl -u ${SERVICE_NAME} --since "1 minute ago" | grep "admin account created." | tail -n 1 | sed -e 's/.*admin account created.//')
        if [ -z "$password" ]; then
            log_error "Could not set default password, please check the error log!"
        fi
        show_access_info "$password" "$LISTEN_PORT"
    else
        log_error "Could not start the Komari service!"
        log_info "View log: journalctl -u ${SERVICE_NAME} -f"
        return 1
    fi
}

# Create systemd service file
create_systemd_service() {
    local port="$1"
    log_step "Creating Komari systemd service..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    cat > "$service_file" << EOF
[Unit]
Description=Komari monitor service
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} server -l 0.0.0.0:${port}
WorkingDirectory=${DATA_DIR}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    log_success "Created Komari systemd service!"
}

# Show access information
show_access_info() {
    local password=$1
    local port=${2:-$DEFAULT_PORT}
    echo
    log_success "Installation complete!"
    echo
    log_info "Usage info:"
    log_info "  URL: http://$(hostname -I | awk '{print $1}'):${port}"
    if [ -n "$password" ]; then
        log_info "Note your initial password as it will only be displayed once!"
        log_info "You can change the password after your first login."
        log_info "Initial password: $password"
    fi
    echo
    log_info "Service control commands:"
    log_info "  Status:  systemctl status $SERVICE_NAME"
    log_info "  Start:   systemctl start $SERVICE_NAME"
    log_info "  Stop:    systemctl stop $SERVICE_NAME"
    log_info "  Restart: systemctl restart $SERVICE_NAME"
    log_info "  Tail log:    journalctl -u $SERVICE_NAME -f"
}

# Upgrade function
upgrade_komari() {
    log_step "Upgrading Komari..."

    if ! is_installed; then
        log_error "There is no existing Komari installation to upgrade."
        return 1
    fi

    if ! check_systemd; then
        log_error "Could not detect systemd; Komari cannot be controlled via service commands."
        return 1
    fi

    log_step "Stopping Komari service..."
    systemctl stop ${SERVICE_NAME}.service

    log_step "Backing up the current Komari binary..."
    cp "$BINARY_PATH" "${BINARY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    local arch
    arch=$(detect_arch)
    local file_name="komari-linux-${arch}"
    local download_url="https://github.com/zejjnt/komari/releases/latest/download/${file_name}"

    log_step "Downloading latest binary..."
    if ! curl -L -o "$BINARY_PATH" "$download_url"; then
        log_error "Download failed; restoring previous binary from backup..."
        mv "${BINARY_PATH}.backup."* "$BINARY_PATH"
        systemctl start ${SERVICE_NAME}.service
        return 1
    fi

    chmod +x "$BINARY_PATH"

    log_step "Restarting the Komari service..."
    systemctl start ${SERVICE_NAME}.service

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log_success "Komari was successfully upgraded!"
    else
        log_error "Could not start the Komari service after the upgrade!"
    fi
}

# Uninstall function
uninstall_komari() {
    log_step "Uninstalling Komari..."

    if ! is_installed; then
        log_info "Komari is not installed."
        return 0
    fi

    read -rp "Do you really want to uninstall Komari?(Y/n): " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        log_info "Uninstaller aborted!"
        return 0
    fi

    if check_systemd; then
        log_step "Stop & disable the Komari service..."
        systemctl stop ${SERVICE_NAME}.service >/dev/null 2>&1
        systemctl disable ${SERVICE_NAME}.service >/dev/null 2>&1
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
        log_success "The Komari service was stopped and removed."
    fi

    log_step "Deleting binaries..."
    rm -f "$BINARY_PATH"
    # Attempting to remove the installation directory if empty
    rmdir "$INSTALL_DIR" 2>/dev/null || log_info "Could not remove the directory $INSTALL_DIR since it still contains files."
    log_success "The Komari binary has been deleted."

    log_success "The Komari service has been stopped."
    log_info "Existing log files in $DATA_DIR will not be removed."
}

# Show service status
show_status() {
    if ! is_installed; then
        log_error "Komari is not installed."
        return
    fi
    if ! check_systemd; then
        log_error "Could not access systemd; unable to obtain service status!"
        return
    fi
    log_step "Komari service status:"
    systemctl status ${SERVICE_NAME}.service --no-pager -l
}

# Show service logs
show_logs() {
    if ! is_installed; then
        log_error "Komari is not installed."
        return
    fi
    if ! check_systemd; then
        log_error "Could not access systemd; unable to retrieve service logs."
        return
    fi
    log_step "View Komari logs..."
    journalctl -u ${SERVICE_NAME} -f --no-pager
}

# Restart service
restart_service() {
    if ! is_installed; then
        log_error "Komari is not installed."
        return
    fi
    if ! check_systemd; then
        log_error "Could not access systemd; unable to restart the Komari service."
        return
    fi
    log_step "Restarting the Komari service..."
    systemctl restart ${SERVICE_NAME}.service
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log_success "Successfully restarted Komari."
    else
        log_error "Failed to restart Komari."
    fi
}

# Stop service
stop_service() {
    if ! is_installed; then
        log_error "Komari is not installed."
        return
    fi
    if ! check_systemd; then
        log_error "Could not access systemd; unable to stop the Komari service."
        return
    fi
    log_step "Disabling the Komari service..."
    systemctl stop ${SERVICE_NAME}.service
    log_success "The Komari service has been stopped."
}


# Main menu
main_menu() {
    show_banner
    echo "Komari setup menu"
    echo "  1) Install Komari"
    echo "  2) Upgrade Komari"
    echo "  3) Uninstall Komari"
    echo "  4) Check status for Komari"
    echo "  5) View Komari logs"
    echo "  6) Restart the Komari service"
    echo "  7) Stop the Komari service"
    echo "  8) Exit menu"
    echo

    read -rp "Select option [1-8]: " choice

    case $choice in
        1) install_binary ;;
        2) upgrade_komari ;;
        3) uninstall_komari ;;
        4) show_status ;;
        5) show_logs ;;
        6) restart_service ;;
        7) stop_service ;;
        8) exit 0 ;;
        *) log_error "Invalid option" ;;
    esac
}

# Main execution
check_root
main_menu
