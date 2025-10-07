# OctoPrint USB File Watcher - Enterprise Deployment

This deployment package provides enterprise-grade auto-mounting functionality for OctoPrint using pmount and systemd services.

## Overview

This package implements your proven pmount + systemd approach with the following components:

- **pmount/pumount**: Safe USB mounting with automatic mount point selection
- **systemd service**: Hardware-level USB device management
- **udev rules**: Automatic device detection and service triggering
- **Multiple mount points**: Supports up to 4 concurrent USB devices (/media/usb1-4)
- **Comprehensive filesystem support**: FAT32, exFAT, NTFS, ext2/3/4
- **Enterprise logging**: Dedicated USB activity logging

## Installation

Run as root on your 3D printer image:

```bash
sudo ./install.sh
```

This will:
1. Install system scripts to `/usr/local/bin/`
2. Install required packages (pmount, ntfs-3g, exfat-fuse, dosfstools)
3. Configure udev rules for USB device detection
4. Set up systemd service for device management
5. Configure sudo permissions for safe mounting
6. Apply OctoPrint plugin settings for enterprise mode

## Architecture

### Filesystem Support
- **FAT32/FAT16**: Native support (most USB drives)
- **exFAT**: Via exfat-fuse package (large files, modern USB drives)
- **NTFS**: Via ntfs-3g package (Windows-formatted drives)
- **ext2/ext3/ext4**: Native Linux support
- **Automatic detection**: pmount handles filesystem type automatically

### Mount Point Strategy
- Uses pmount for safe mounting with `/media/usb1` through `/media/usb4`
- Automatically finds available mount points
- Prevents conflicts with multiple devices
- No root privileges required during operation (only for setup)

### Device Detection Flow
1. USB device inserted → udev rule triggers
2. systemd service `usbstick-handler@.service` starts
3. `usb-gcode-mount.sh` mounts device using pmount
4. OctoPrint plugin detects new files and begins monitoring
5. Files copied automatically to OctoPrint
6. Auto-unmount after configurable delay using pumount

### Safety Features
- Uses pmount/pumount for safe mounting/unmounting
- Systemd service isolation prevents conflicts
- Multiple mount point support prevents device collisions
- Enterprise logging to dedicated USB log file
- Automatic filesystem detection and mounting
- Safe device removal with configurable delays
- No root privileges required during normal operation

## Configuration

### Default Watch Folders
The plugin monitors these folders automatically:
- `/media/usb1` - Primary USB mount point
- `/media/usb2` - Secondary USB mount point
- `/media/usb3` - Tertiary USB mount point
- `/media/usb4` - Quaternary USB mount point

### Enterprise Settings
Automatically configured during installation:
- `enterpriseMode`: true (enables auto-mounting features)
- `autoUnmount`: true (auto-unmount after file copy)
- `unmountDelay`: 30 seconds (configurable delay before unmount)
- `watchFolders`: ["/media/usb1", "/media/usb2", "/media/usb3", "/media/usb4"]
- `extensions`: [".gcode", ".gco", ".g"] (supported file types)

### Customization Options
Edit `/home/pi/.octoprint/config.yaml` or use OctoPrint settings interface:
```yaml
plugins:
  usbfilewatcher:
    unmountDelay: 60  # Increase delay for slower operations
    extensions: [".gcode", ".gco", ".g", ".stl"]  # Add STL files
    debug_logging: true  # Enable detailed logging
```

## Troubleshooting

### Log Monitoring
Check logs for issues:
```bash
# Plugin activity logs
tail -f ~/.octoprint/logs/usbfilewatcher-usb.log

# System USB events
sudo journalctl -u usbstick-handler@* -f

# Real-time USB device events
sudo udevadm monitor --property --subsystem-match=block

# System mount logs
sudo journalctl -f | grep -i usb
```

### Device Status Verification
```bash
# Check current mounts
mount | grep /media/usb
sudo pmount --list

# Test USB detection
sudo udevadm test /dev/sdb1  # Replace with your device

# Verify udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Common Issues & Solutions

**USB Device Not Detected:**
```bash
# Check if device is recognized
lsblk
sudo fdisk -l

# Verify udev rule activation
sudo udevadm info -a -n /dev/sdb1  # Replace with your device
```

**Mount Failures:**
```bash
# Check filesystem type
sudo blkid /dev/sdb1

# Manual mount test
sudo pmount /dev/sdb1 usb1

# Check for filesystem errors
sudo fsck /dev/sdb1  # Use appropriate filesystem checker
```

**NTFS/exFAT Issues:**
```bash
# Verify filesystem support packages
dpkg -l | grep -E "(ntfs-3g|exfat)"

# Reinstall if needed
sudo apt-get install --reinstall ntfs-3g exfat-fuse exfat-utils
```

**Permission Problems:**
```bash
# Check sudo permissions
sudo -l -U pi

# Verify sudoers configuration
sudo visudo -f /etc/sudoers.d/usb-gcode
```

## Requirements

### System Requirements
- **Linux Distribution**: systemd-enabled (Ubuntu, Debian, Raspberry Pi OS)
- **OctoPrint**: 1.11.0+ with USB File Watcher plugin installed
- **Python**: 3.7 - 3.13.7 (tested and verified)
- **Root Access**: Required for initial installation only

### Automatically Installed Packages
The installation script will install these packages if not present:
- **pmount**: Safe USB mounting without root privileges
- **ntfs-3g**: NTFS filesystem support (Windows USB drives)
- **exfat-fuse**: exFAT filesystem support (modern large USB drives)
- **exfat-utils**: exFAT filesystem utilities
- **dosfstools**: FAT filesystem utilities (most common USB format)

### Network Requirements
- Internet connection during installation (for package downloads)
- No ongoing network requirements for operation

## Production Deployment

### For 3D Printer Fleets
This enterprise deployment is specifically designed for:
- **Manufacturing environments** with multiple 3D printers
- **Educational institutions** with shared 3D printing resources
- **Makerspaces** requiring reliable USB file transfer
- **Production facilities** needing automated G-code deployment

### Fleet Installation
```bash
# On each 3D printer system:
git clone https://github.com/Garr-Garr/OctoPrint-usbFileWatcher.git
cd OctoPrint-usbFileWatcher/deployment
sudo ./install.sh

# Or for automated deployment:
wget -O- https://raw.githubusercontent.com/Garr-Garr/OctoPrint-usbFileWatcher/installer/deployment/install.sh | sudo bash
```

### Image Building
Include in your custom 3D printer images:
1. **Base Image**: Start with OctoPrint-enabled Linux distribution
2. **Plugin Installation**: Install USB File Watcher plugin
3. **Enterprise Setup**: Run deployment script during image build
4. **Configuration**: Customize settings in `/deployment/config/enterprise-settings.json`
5. **Testing**: Verify auto-mounting with test USB devices

This approach provides the enterprise reliability you need for your 3D printer fleet deployment with comprehensive filesystem support and robust error handling.
