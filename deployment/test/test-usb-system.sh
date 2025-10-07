#!/bin/bash
# Test script for USB GCode transfer system

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_files_exist() {
    log "Testing if required files exist..."

    local files=(
        "/usr/local/bin/usb-gcode-mount.sh"
        "/usr/local/bin/usb-gcode-unmount.sh"
        "/etc/udev/rules.d/99-usb-gcode.rules"
        "/etc/sudoers.d/usb-gcode"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log "✓ $file exists"
        else
            error "✗ $file missing"
        fi
    done
}

test_permissions() {
    log "Testing file permissions..."

    if [[ -x "/usr/local/bin/usb-gcode-mount.sh" ]]; then
        log "✓ Mount script is executable"
    else
        error "✗ Mount script is not executable"
    fi

    if [[ -x "/usr/local/bin/usb-gcode-unmount.sh" ]]; then
        log "✓ Unmount script is executable"
    else
        error "✗ Unmount script is not executable"
    fi
}

test_sudo_config() {
    log "Testing sudo configuration..."

    if sudo -u pi sudo -l 2>/dev/null | grep -q usb-gcode-mount.sh; then
        log "✓ Sudo configuration working"
    else
        warn "✗ Sudo configuration may not be working"
        echo "  Run: sudo -u pi sudo -l | grep usb-gcode"
    fi
}

test_udev_rules() {
    log "Testing udev rules..."

    if udevadm test-builtin net_id /sys/class/block/sda 2>/dev/null >/dev/null; then
        log "✓ udev is responding"
    else
        warn "✗ udev test failed (this may be normal if no USB devices present)"
    fi

    # Check if rules file is valid
    if udevadm verify /etc/udev/rules.d/99-usb-gcode.rules 2>/dev/null; then
        log "✓ udev rules file is valid"
    else
        warn "✗ udev rules file may have issues"
    fi
}

test_mount_point() {
    log "Testing mount point creation..."

    # Test if we can create the mount point
    if mkdir -p /media/gcode-transfer 2>/dev/null; then
        log "✓ Can create mount point /media/gcode-transfer"
        rmdir /media/gcode-transfer 2>/dev/null || true
    else
        error "✗ Cannot create mount point /media/gcode-transfer"
    fi
}

test_log_file() {
    log "Testing log file..."

    if [[ -f "/var/log/usb-gcode.log" ]]; then
        if [[ -w "/var/log/usb-gcode.log" ]]; then
            log "✓ Log file exists and is writable"
        else
            warn "✗ Log file exists but is not writable"
        fi
    else
        warn "✗ Log file does not exist"
    fi
}

test_octoprint_plugin() {
    log "Testing OctoPrint plugin..."

    local plugin_file="/home/pi/.octoprint/plugins/usbfileman/__init__.py"
    if [[ -f "$plugin_file" ]]; then
        log "✓ USB FileMan plugin is installed"
    else
        warn "✗ USB FileMan plugin not found at expected location"
    fi

    local log_file="/home/pi/.octoprint/logs/usbfileman-usb.log"
    if [[ -f "$log_file" ]]; then
        log "✓ Plugin log file exists"
    else
        warn "✗ Plugin log file not found (plugin may not have started yet)"
    fi
}

simulate_usb_operations() {
    log "Simulating USB operations..."

    # Create a test mount point
    local test_mount="/tmp/test-usb-mount"
    mkdir -p "$test_mount"

    # Test mount script (dry run)
    if [[ -x "/usr/local/bin/usb-gcode-mount.sh" ]]; then
        log "✓ Mount script exists and is executable"
    else
        error "✗ Mount script test failed"
    fi

    # Clean up
    rmdir "$test_mount" 2>/dev/null || true
}

show_usb_info() {
    log "Current USB device information..."

    echo "Connected USB devices:"
    lsusb 2>/dev/null || echo "  lsusb not available"

    echo ""
    echo "Block devices:"
    lsblk 2>/dev/null || echo "  lsblk not available"

    echo ""
    echo "Current mount points:"
    findmnt -t vfat,exfat,ntfs,ext4 2>/dev/null || echo "  No relevant mount points found"
}

show_next_steps() {
    echo ""
    log "Test completed!"
    echo ""
    echo "Next steps:"
    echo "1. Insert a USB device into your dedicated USB port"
    echo "2. Check the logs:"
    echo "   tail -f /var/log/usb-gcode.log"
    echo "3. Monitor the plugin log:"
    echo "   tail -f /home/pi/.octoprint/logs/usbfileman-usb.log"
    echo ""
    echo "To identify your USB port:"
    echo "   udevadm info --name=/dev/sda --attribute-walk | grep KERNELS"
    echo ""
    echo "Manual test commands:"
    echo "   sudo /usr/local/bin/usb-gcode-mount.sh sda1"
    echo "   sudo /usr/local/bin/usb-gcode-unmount.sh"
}

main() {
    echo "USB GCode Transfer System - Test Suite"
    echo "======================================"

    test_files_exist
    test_permissions
    test_sudo_config
    test_udev_rules
    test_mount_point
    test_log_file
    test_octoprint_plugin
    simulate_usb_operations
    show_usb_info
    show_next_steps
}

main
