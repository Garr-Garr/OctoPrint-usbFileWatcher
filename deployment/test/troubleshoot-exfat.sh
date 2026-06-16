#!/bin/bash
# USB exFAT Troubleshooting Script for OctoPrint USB File Watcher
# Usage: ./troubleshoot-exfat.sh [device] (e.g. ./troubleshoot-exfat.sh /dev/sda1)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

USB_DEVICE="$1"

main() {
    echo "USB exFAT Troubleshooting for OctoPrint USB File Watcher"
    echo "========================================================"
    echo ""
    
    # Step 1: Check system packages
    log "Step 1: Checking system packages..."
    
    packages=("pmount" "exfat-fuse" "exfat-utils" "dosfstools")
    missing_packages=()
    
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            log "✓ $package is installed"
        else
            warn "✗ $package is NOT installed"
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo ""
        error "Missing packages detected. Install with:"
        echo "sudo apt-get update"
        echo "sudo apt-get install ${missing_packages[*]}"
        echo ""
    fi
    
    # Step 2: Check kernel modules
    log "Step 2: Checking kernel modules..."
    
    if lsmod | grep -q "exfat"; then
        log "✓ exFAT kernel module is loaded"
    else
        warn "✗ exFAT kernel module not loaded"
        debug "Try: sudo modprobe exfat"
    fi
    
    # Step 3: Check USB devices
    log "Step 3: Detecting USB devices..."
    
    echo "All USB storage devices:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -E "(NAME|usb|sd[a-z])" || warn "No USB devices found"
    
    echo ""
    echo "USB devices with filesystem info:"
    sudo blkid | grep -E "(sd[a-z]|usb)" || warn "No USB devices with filesystems found"
    
    # Step 4: Test specific device if provided
    if [ -n "$USB_DEVICE" ]; then
        log "Step 4: Testing specific device: $USB_DEVICE"
        
        if [ -b "$USB_DEVICE" ]; then
            log "✓ Device $USB_DEVICE exists"
            
            # Get filesystem info
            FS_TYPE=$(sudo blkid -o value -s TYPE "$USB_DEVICE" 2>/dev/null || echo "unknown")
            log "Filesystem type: $FS_TYPE"
            
            if [ "$FS_TYPE" = "exfat" ]; then
                log "✓ Device is exFAT formatted"
                
                # Test manual mount
                test_manual_mount "$USB_DEVICE"
                
            else
                warn "Device is not exFAT (detected: $FS_TYPE)"
            fi
        else
            error "Device $USB_DEVICE does not exist"
        fi
    else
        log "Step 4: No specific device provided (use: $0 /dev/sda1)"
    fi
    
    # Step 5: Check mount points
    log "Step 5: Checking mount points..."
    
    for mount in /media/usb1 /media/usb2 /media/usb3 /media/usb4; do
        if [ -d "$mount" ]; then
            if mountpoint -q "$mount"; then
                MOUNTED_DEVICE=$(findmnt -n -o SOURCE "$mount")
                FS_TYPE=$(findmnt -n -o FSTYPE "$mount")
                log "✓ $mount is mounted ($MOUNTED_DEVICE, $FS_TYPE)"
            else
                debug "$mount exists but not mounted"
            fi
        else
            debug "$mount does not exist"
        fi
    done
    
    # Step 6: Check systemd services
    log "Step 6: Checking systemd services..."
    
    if systemctl list-units --type=service | grep -q "usbstick-handler"; then
        log "✓ USB handler services are active"
        systemctl status "usbstick-handler@*" --no-pager || true
    else
        warn "✗ No USB handler services found"
        debug "Check if enterprise installation was completed"
    fi
    
    # Step 7: Check logs
    log "Step 7: Checking recent logs..."
    
    echo ""
    echo "Recent systemd USB events:"
    journalctl -u "usbstick-handler@*" --since "10 minutes ago" --no-pager || warn "No recent systemd events"
    
    echo ""
    echo "Recent USB mount logs:"
    if [ -f "/var/log/usb-gcode.log" ]; then
        tail -20 /var/log/usb-gcode.log || warn "Could not read USB log"
    else
        warn "USB log file not found at /var/log/usb-gcode.log"
    fi
    
    echo ""
    echo "Recent plugin logs:"
    if [ -f "/home/pi/.octoprint/logs/usbfilewatcher-usb.log" ]; then
        tail -20 /home/pi/.octoprint/logs/usbfilewatcher-usb.log || warn "Could not read plugin log"
    else
        warn "Plugin log file not found"
    fi
    
    # Step 8: Test commands
    log "Step 8: Manual testing commands..."
    
    echo ""
    echo "Manual testing commands to try:"
    echo "==============================="
    echo ""
    echo "1. Check if exFAT tools work:"
    echo "   which mount.exfat"
    echo "   mount.exfat --help"
    echo ""
    echo "2. Monitor USB events in real-time:"
    echo "   sudo udevadm monitor --property --subsystem-match=block"
    echo ""
    echo "3. Test manual mount (replace /dev/sda1 with your device):"
    echo "   sudo mkdir -p /media/test-exfat"
    echo "   sudo mount -t exfat /dev/sda1 /media/test-exfat"
    echo "   ls -la /media/test-exfat/"
    echo "   sudo umount /media/test-exfat"
    echo ""
    echo "4. Test pmount (replace sda1 with your device):"
    echo "   sudo pmount /dev/sda1 test-mount"
    echo "   ls -la /media/test-mount/"
    echo "   sudo pumount /dev/sda1"
    echo ""
    echo "5. Check udev rules:"
    echo "   cat /etc/udev/rules.d/99-usb-gcode.rules"
    echo "   sudo udevadm control --reload-rules"
    echo "   sudo udevadm trigger"
    echo ""
    echo "6. Force plugin scan:"
    echo "   curl -s 'http://localhost:5000/api/plugin/usbfilewatcher'"
    echo ""
}

test_manual_mount() {
    local device="$1"
    log "Testing manual mount of $device..."
    
    # Create temporary mount point
    local temp_mount="/media/test-exfat-$$"
    sudo mkdir -p "$temp_mount"
    
    # Test direct mount
    if sudo mount -t exfat "$device" "$temp_mount" 2>/dev/null; then
        log "✓ Direct mount successful"
        ls -la "$temp_mount" | head -5
        sudo umount "$temp_mount"
    else
        warn "✗ Direct mount failed"
        debug "Error: $(sudo mount -t exfat "$device" "$temp_mount" 2>&1 || true)"
    fi
    
    # Test pmount
    local pmount_name="test-$(basename "$device")"
    if sudo pmount "$device" "$pmount_name" 2>/dev/null; then
        log "✓ pmount successful"
        ls -la "/media/$pmount_name" | head -5
        sudo pumount "$device"
    else
        warn "✗ pmount failed"
        debug "Error: $(sudo pmount "$device" "$pmount_name" 2>&1 || true)"
    fi
    
    # Clean up
    sudo rmdir "$temp_mount" 2>/dev/null || true
}

# Auto-detect USB device if not provided
if [ -z "$USB_DEVICE" ]; then
    # Try to find an exFAT USB device
    for device in /dev/sd[a-z][0-9]; do
        if [ -b "$device" ]; then
            FS_TYPE=$(sudo blkid -o value -s TYPE "$device" 2>/dev/null || echo "")
            if [ "$FS_TYPE" = "exfat" ]; then
                USB_DEVICE="$device"
                log "Auto-detected exFAT device: $USB_DEVICE"
                break
            fi
        fi
    done
fi

# Run the main troubleshooting
main
