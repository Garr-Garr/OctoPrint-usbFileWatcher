#!/bin/bash
# Test filesystem support for USB File Watcher
# Usage: ./test-filesystem-support.sh

set -e

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
}

test_package() {
    local package="$1"
    local description="$2"
    
    if dpkg -l | grep -q "^ii  $package "; then
        log "$description: ✓ Installed ($package)"
        return 0
    else
        warn "$description: ✗ Not installed ($package)"
        return 1
    fi
}

test_filesystem_support() {
    local filesystem="$1"
    local mount_cmd="$2"
    local description="$3"
    
    if command -v "$mount_cmd" >/dev/null 2>&1; then
        log "$description: ✓ Available ($mount_cmd found)"
        return 0
    else
        warn "$description: ✗ Not available ($mount_cmd not found)"
        return 1
    fi
}

main() {
    echo "USB File Watcher Filesystem Support Test"
    echo "========================================"
    echo ""
    
    log "Testing required packages..."
    
    # Test core packages
    test_package "pmount" "Safe mounting utility"
    test_package "dosfstools" "FAT32/FAT16 tools"
    test_package "ntfs-3g" "NTFS filesystem support"
    test_package "exfat-fuse" "exFAT filesystem support"
    test_package "exfat-utils" "exFAT utilities"
    
    echo ""
    log "Testing filesystem mount capabilities..."
    
    # Test filesystem support
    test_filesystem_support "FAT32" "mount.vfat" "FAT32/FAT16 support"
    test_filesystem_support "NTFS" "mount.ntfs-3g" "NTFS support"
    test_filesystem_support "exFAT" "mount.exfat" "exFAT support"
    test_filesystem_support "ext4" "mount.ext4" "ext4 support"
    
    echo ""
    log "Testing pmount functionality..."
    
    # Test pmount
    if command -v pmount >/dev/null 2>&1; then
        log "pmount: ✓ Available"
        
        # Test if user can use pmount
        if groups "$USER" | grep -q "plugdev"; then
            log "User permissions: ✓ User is in 'plugdev' group"
        else
            warn "User permissions: ✗ User not in 'plugdev' group (may need sudo)"
        fi
    else
        error "pmount: ✗ Not found - install with: apt-get install pmount"
    fi
    
    echo ""
    log "Checking mount points..."
    
    # Check mount points
    for mount in /media/usb1 /media/usb2 /media/usb3 /media/usb4; do
        if [ -d "$mount" ]; then
            log "Mount point $mount: ✓ Exists"
        else
            warn "Mount point $mount: ✗ Missing (will be created automatically)"
        fi
    done
    
    echo ""
    log "Testing connected USB devices..."
    
    # List USB storage devices
    if command -v lsblk >/dev/null 2>&1; then
        echo "Current USB storage devices:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -E "(NAME|usb|sd[a-z])" || log "No USB devices detected"
    fi
    
    echo ""
    echo "Troubleshooting Commands:"
    echo "========================"
    echo ""
    echo "Install missing packages:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install pmount ntfs-3g exfat-fuse exfat-utils dosfstools"
    echo ""
    echo "Check USB device filesystem:"
    echo "  lsblk -f"
    echo "  sudo blkid /dev/sda1"
    echo ""
    echo "Manual mount test:"
    echo "  sudo pmount /dev/sda1 usb1"
    echo "  ls -la /media/usb1/"
    echo "  sudo pumount /dev/sda1"
    echo ""
    echo "Check system logs:"
    echo "  journalctl -f -u 'usbstick-handler@*'"
    echo "  tail -f /var/log/usb-gcode.log"
    echo ""
}

# Run the test
main
