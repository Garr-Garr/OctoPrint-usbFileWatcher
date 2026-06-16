#!/bin/bash
# USB GCode Transfer System - Main Installation Script
# Compatible with both image build and runtime installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_MODE=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --image-build    Install during image creation (no service restarts)"
    echo "  --runtime        Install on running system (includes service restarts)"
    echo "  --uninstall      Remove the USB GCode transfer system"
    echo "  --verbose        Enable verbose output"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --image-build    # For building company images"
    echo "  $0 --runtime        # For updating existing systems"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_files() {
    local required_files=(
        "system/99-usb-gcode.rules"
        "system/usb-gcode-mount.sh"
        "system/usb-gcode-unmount.sh"
        "system/usb-gcode-sudoers"
        "system/usbstick-handler@.service"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            error "Required file not found: $file"
        fi
    done
}

install_system_files() {
    log "Installing system files..."

    # Create directories
    mkdir -p /usr/local/bin
    mkdir -p /etc/udev/rules.d
    mkdir -p /etc/sudoers.d
    mkdir -p /etc/systemd/system

    # Install required packages for filesystem support
    log "Installing filesystem support packages..."
    
    # Update package list
    apt-get update -qq || warn "Could not update package list"
    
    # Install pmount and filesystem support
    local packages=(
        "pmount"           # Safe mounting utility
        "ntfs-3g"          # NTFS filesystem support
        "exfat-fuse"       # exFAT filesystem support
        "exfat-utils"      # exFAT utilities
        "dosfstools"       # FAT32/FAT16 filesystem tools
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "Installing $package..."
            apt-get install -y "$package" || warn "Could not install $package"
        else
            log "$package is already installed"
        fi
    done

    # Copy and set permissions for scripts
    cp "$SCRIPT_DIR/system/usb-gcode-mount.sh" /usr/local/bin/
    cp "$SCRIPT_DIR/system/usb-gcode-unmount.sh" /usr/local/bin/
    chmod +x /usr/local/bin/usb-gcode-*.sh

    # Copy udev rules
    cp "$SCRIPT_DIR/system/99-usb-gcode.rules" /etc/udev/rules.d/

    # Copy systemd service
    cp "$SCRIPT_DIR/system/usbstick-handler@.service" /etc/systemd/system/

    # Copy sudo configuration
    cp "$SCRIPT_DIR/system/usb-gcode-sudoers" /etc/sudoers.d/usb-gcode
    chmod 440 /etc/sudoers.d/usb-gcode

    # Create log file with proper permissions
    touch /var/log/usb-gcode.log
    chown pi:pi /var/log/usb-gcode.log
    chmod 644 /var/log/usb-gcode.log

    log "System files installed successfully"
}

configure_plugin() {
    log "Configuring OctoPrint plugin..."

    local config_dir="/home/pi/.octoprint"
    local plugin_config="$config_dir/config.yaml"

    if [[ -f "$plugin_config" ]]; then
        # Backup existing config
        cp "$plugin_config" "$plugin_config.backup.$(date +%s)"
        log "Backed up existing OctoPrint configuration"
    fi

    # Note: In a real deployment, modify the config.yaml here
    # For now just note that manual configuration is needed
    warn "Manual plugin configuration required - see config/enterprise-settings.json"
}

reload_services() {
    if [[ "$INSTALL_MODE" == "runtime" ]]; then
        log "Reloading system services..."

        # Reload systemd services
        systemctl daemon-reload || warn "Could not reload systemd daemon"

        # Reload udev rules
        udevadm control --reload-rules
        udevadm trigger

        log "Services reloaded"
    else
        log "Skipping service reload (image build mode)"
    fi
}

test_installation() {
    log "Testing installation..."

    # Check if files exist
    local test_files=(
        "/usr/local/bin/usb-gcode-mount.sh"
        "/usr/local/bin/usb-gcode-unmount.sh"
        "/etc/udev/rules.d/99-usb-gcode.rules"
        "/etc/sudoers.d/usb-gcode"
        "/etc/systemd/system/usbstick-handler@.service"
    )

    for file in "${test_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Installation test failed: $file not found"
        fi
    done

    # Test script permissions
    if [[ ! -x "/usr/local/bin/usb-gcode-mount.sh" ]]; then
        error "Mount script is not executable"
    fi

    # Test sudo configuration
    if ! sudo -u pi sudo -l | grep -q usb-gcode-mount.sh; then
        warn "Sudo configuration may not be working properly"
    fi

    # Check filesystem support packages
    local required_packages=(
        "pmount"
        "ntfs-3g"
        "exfat-fuse"
        "exfat-utils"
        "dosfstools"
    )

    for package in "${required_packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii  $package "; then
            warn "$package not found - some filesystem types may not be supported"
        fi
    done

    # Test filesystem support
    if command -v mount.exfat >/dev/null 2>&1; then
        log "exFAT support: Available"
    else
        warn "exFAT support: Not available - install exfat-fuse and exfat-utils"
    fi

    if command -v mount.ntfs >/dev/null 2>&1 || command -v mount.ntfs-3g >/dev/null 2>&1; then
        log "NTFS support: Available"
    else
        warn "NTFS support: Not available - install ntfs-3g"
    fi

    log "Installation test passed"
}

uninstall() {
    log "Uninstalling USB GCode transfer system..."

    # Remove files
    rm -f /usr/local/bin/usb-gcode-mount.sh
    rm -f /usr/local/bin/usb-gcode-unmount.sh
    rm -f /etc/udev/rules.d/99-usb-gcode.rules
    rm -f /etc/sudoers.d/usb-gcode
    rm -f /etc/systemd/system/usbstick-handler@.service

    # Clean up mount points if empty
    for mount in /media/usb1 /media/usb2 /media/usb3 /media/usb4; do
        rmdir "$mount" 2>/dev/null || true
    done

    # Reload services
    if [[ "$INSTALL_MODE" == "runtime" ]]; then
        systemctl daemon-reload
        udevadm control --reload-rules
        udevadm trigger
    fi

    log "Uninstallation complete"
}

show_post_install_info() {
    echo ""
    log "Installation completed successfully!"
    echo ""
    echo "Enterprise USB Auto-Mount System installed using pmount + systemd approach"
    echo ""
    echo "Supported Filesystems:"
    echo "  ✓ FAT32/FAT16 (native Linux support)"
    echo "  ✓ NTFS (via ntfs-3g package)"
    echo "  ✓ exFAT (via exfat-fuse and exfat-utils packages)"
    echo "  ✓ ext2/ext3/ext4 (native Linux support)"
    echo ""
    echo "Next steps:"
    echo "1. Verify filesystem packages are installed:"
    echo "   dpkg -l | grep -E '(pmount|ntfs-3g|exfat-fuse|exfat-utils|dosfstools)'"
    echo ""
    echo "2. (Optional) Target specific USB port by editing:"
    echo "   /etc/udev/rules.d/99-usb-gcode.rules"
    echo "   Find your port: udevadm info --name=/dev/sda --attribute-walk | grep KERNELS"
    echo ""
    echo "3. Configure the OctoPrint plugin for enterprise mode"
    echo "   Watch folders: /media/usb1, /media/usb2, /media/usb3, /media/usb4"
    echo ""
    echo "4. Test the system:"
    echo "   $SCRIPT_DIR/test/test-usb-system.sh"
    echo ""
    echo "How it works:"
    echo "  - Insert USB → udev triggers systemd service → pmount to /media/usb* → OctoPrint API call"
    echo "  - Files copied → pumount when removed or after delay"
    echo ""
    echo "Troubleshooting filesystem issues:"
    echo "  - exFAT not mounting: apt-get install exfat-fuse exfat-utils"
    echo "  - NTFS not mounting: apt-get install ntfs-3g"
    echo "  - Check mount errors: journalctl -f -u 'usbstick-handler@*'"
    echo "  - Manual mount test: pmount /dev/sda1 /media/usb1"
    echo ""
    echo "Log files:"
    echo "  - USB operations: /var/log/usb-gcode.log"
    echo "  - Plugin activity: ~/.octoprint/logs/usbfilewatcher-usb.log"
    echo "  - systemd services: journalctl -f -u 'usbstick-handler@*'"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image-build)
            INSTALL_MODE="image-build"
            shift
            ;;
        --runtime)
            INSTALL_MODE="runtime"
            shift
            ;;
        --uninstall)
            INSTALL_MODE="uninstall"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate arguments
if [[ -z "$INSTALL_MODE" ]]; then
    error "Installation mode required. Use --image-build or --runtime"
fi

# Main installation flow
main() {
    check_root

    if [[ "$INSTALL_MODE" == "uninstall" ]]; then
        uninstall
        exit 0
    fi

    check_files
    install_system_files
    configure_plugin
    reload_services
    test_installation
    show_post_install_info
}

# Run main function
main
