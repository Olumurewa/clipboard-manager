#!/bin/bash

set -eo pipefail
if [[ "$1" == "-x" ]]; then
    set -x
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $timestamp - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $timestamp - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $timestamp - $message" >&2 ;;
        *) echo "$timestamp - $message" ;;
    esac
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_package() {
    local pkg=$1
    if dpkg -l | grep -q "^ii  $pkg "; then
        log "INFO" "Package $pkg is already installed"
    else
        log "INFO" "Installing $pkg..."
        sudo apt-get install -y "$pkg" || {
            log "ERROR" "Failed to install $pkg"
            return 1
        }
    fi
}

if [ -z "$SUDO_USER" ]; then
    CURRENT_USER=$(logname 2>/dev/null || echo "$USER")
else
    CURRENT_USER="$SUDO_USER"
fi
HOME_DIR=$(eval echo ~"$CURRENT_USER")

if [ "$(id -u)" -eq 0 ]; then
    log "ERROR" "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

LOG_DIR="$HOME_DIR/.local/log/clipboard-manager"
sudo -u "$CURRENT_USER" mkdir -p "$LOG_DIR"
INSTALL_LOG="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$INSTALL_LOG") 2>&1

log "INFO" "Starting Clipboard Manager installation"
log "INFO" "User: $CURRENT_USER"
log "INFO" "Home directory: $HOME_DIR"

log "INFO" "Updating package lists..."
sudo apt-get update || {
    log "ERROR" "Failed to update package lists"
    exit 1
}

log "INFO" "Installing system dependencies..."
DEPENDENCIES=(
    python3
    python3-pip
    python3-venv
    python3-pyqt5
    libxcb-xinerama0
    libxcb-cursor0
    libxkbcommon-x11-0
    x11-xserver-utils
    xclip
    xdotool
)

for pkg in "${DEPENDENCIES[@]}"; do
    install_package "$pkg" || exit 1
done

VENV_DIR="$HOME_DIR/.clipboard-manager-venv"
if [ -d "$VENV_DIR" ]; then
    log "WARNING" "Virtual environment already exists at $VENV_DIR"
    read -rp "Do you want to recreate it? [y/N] " recreate
    if [[ "$recreate" =~ ^[Yy]$ ]]; then
        log "INFO" "Removing existing virtual environment..."
        rm -rf "$VENV_DIR" || {
            log "ERROR" "Failed to remove existing virtual environment"
            exit 1
        }
    else
        log "INFO" "Using existing virtual environment"
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    log "INFO" "Creating Python virtual environment..."
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_DIR" || {
        log "ERROR" "Failed to create virtual environment"
        exit 1
    }
fi

log "INFO" "Installing Python packages..."
sudo -u "$CURRENT_USER" bash <<EOF
source "$VENV_DIR/bin/activate"
pip install --upgrade pip || { echo "Failed to upgrade pip"; exit 1; }
pip install PyQt5 pyperclip pynput || { echo "Failed to install Python packages"; exit 1; }
deactivate
EOF

INSTALL_DIR="$HOME_DIR/.local/bin"
sudo -u "$CURRENT_USER" mkdir -p "$INSTALL_DIR"

if [ -f "$INSTALL_DIR/clipboard-manager.py" ]; then
    BACKUP_DIR="$HOME_DIR/.local/backup/clipboard-manager"
    sudo -u "$CURRENT_USER" mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/clipboard-manager_$(date +%Y%m%d_%H%M%S).py"
    log "INFO" "Backing up existing clipboard manager to $BACKUP_FILE"
    sudo -u "$CURRENT_USER" cp "$INSTALL_DIR/clipboard-manager.py" "$BACKUP_FILE"
fi

SCRIPT_SOURCE="$(dirname "$(realpath "$0")")/clipboard_manager.py"
if [ ! -f "$SCRIPT_SOURCE" ]; then
    log "ERROR" "Could not find clipboard_manager.py in the current directory"
    exit 1
fi

log "INFO" "Copying clipboard manager script..."
sudo -u "$CURRENT_USER" cp "$SCRIPT_SOURCE" "$INSTALL_DIR/clipboard-manager.py" || {
    log "ERROR" "Failed to copy clipboard manager script"
    exit 1
}

log "INFO" "Creating executable wrapper..."
sudo -u "$CURRENT_USER" tee "$INSTALL_DIR/clipboard-manager" > /dev/null << 'EOL'
#!/bin/bash
source "$HOME/.clipboard-manager-venv/bin/activate"
python "$HOME/.local/bin/clipboard-manager.py" "$@"
deactivate
EOL

log "INFO" "Setting executable permissions..."
sudo -u "$CURRENT_USER" chmod +x "$INSTALL_DIR/clipboard-manager.py"
sudo -u "$CURRENT_USER" chmod +x "$INSTALL_DIR/clipboard-manager"

DESKTOP_DIR="$HOME_DIR/.local/share/applications"
sudo -u "$CURRENT_USER" mkdir -p "$DESKTOP_DIR"

log "INFO" "Creating desktop entry..."
sudo -u "$CURRENT_USER" tee "$DESKTOP_DIR/clipboard-manager.desktop" > /dev/null << EOL
[Desktop Entry]
Version=1.0
Name=Clipboard Manager
Comment=Advanced Clipboard Management Tool
Exec=$INSTALL_DIR/clipboard-manager
Icon=edit-copy
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOL

if ! grep -q "$HOME_DIR/.local/bin" "$HOME_DIR/.bashrc"; then
    log "INFO" "Adding ~/.local/bin to PATH in .bashrc"
    sudo -u "$CURRENT_USER" tee -a "$HOME_DIR/.bashrc" > /dev/null << EOL

# Added by Clipboard Manager installer
export PATH="\$PATH:$HOME_DIR/.local/bin"
EOL
fi

if command_exists systemctl && [ -d "$HOME_DIR/.config/systemd/user" ] && [ -n "$DISPLAY" ]; then
    log "INFO" "Creating systemd user service..."
    sudo -u "$CURRENT_USER" mkdir -p "$HOME_DIR/.config/systemd/user"
    sudo -u "$CURRENT_USER" tee "$HOME_DIR/.config/systemd/user/clipboard-manager.service" > /dev/null << EOL
[Unit]
Description=Clipboard Manager
After=graphical-session.target

[Service]
ExecStart=$INSTALL_DIR/clipboard-manager
Restart=on-failure
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOL

    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
        log "INFO" "Enabling and starting the service..."
        sudo -u "$CURRENT_USER" XDG_RUNTIME_DIR=/run/user/$(id -u "$CURRENT_USER") \
            systemctl --user daemon-reload && \
        sudo -u "$CURRENT_USER" XDG_RUNTIME_DIR=/run/user/$(id -u "$CURRENT_USER") \
            systemctl --user enable clipboard-manager.service && \
        sudo -u "$CURRENT_USER" XDG_RUNTIME_DIR=/run/user/$(id -u "$CURRENT_USER") \
            systemctl --user start clipboard-manager.service || \
        log "WARNING" "Could not enable/start service (no DBUS session available)"
    else
        log "WARNING" "DBUS session not available - service created but not enabled"
    fi
elif [ ! -n "$DISPLAY" ]; then
    log "WARNING" "Not in a graphical environment - skipping systemd service creation"
else
    log "WARNING" "systemd not available - skipping service creation"
fi

log "INFO" "Creating autostart entry..."
AUTOSTART_DIR="$HOME_DIR/.config/autostart"
sudo -u "$CURRENT_USER" mkdir -p "$AUTOSTART_DIR"
sudo -u "$CURRENT_USER" cp "$DESKTOP_DIR/clipboard-manager.desktop" "$AUTOSTART_DIR/"

log "INFO" "Verifying installation..."
if [ -x "$INSTALL_DIR/clipboard-manager" ] && [ -f "$INSTALL_DIR/clipboard-manager.py" ]; then
    log "SUCCESS" "Clipboard Manager installed successfully!"
    log "INFO" "You can now run it with:"
    log "INFO" "  $ clipboard-manager"
    log "INFO" "Or find it in your application menu"
    
    read -rp "Would you like to start Clipboard Manager now? [Y/n] " start_now
    if [[ "$start_now" =~ ^[Yy]?$ ]]; then
        log "INFO" "Starting Clipboard Manager..."
        nohup sudo -u "$CURRENT_USER" "$INSTALL_DIR/clipboard-manager" >/dev/null 2>&1 &
    fi
else
    log "ERROR" "Installation verification failed"
    exit 1
fi

log "INFO" "Installation log saved to: $INSTALL_LOG"
exit 0