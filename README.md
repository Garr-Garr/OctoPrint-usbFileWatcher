# OctoPrint-usbFileWatcher

USB File Watcher is an enterprise-grade OctoPrint plugin that provides automatic USB device detection, mounting, and file management for 3D printer workflows. Originally designed for easy USB flashdrive interaction, it now includes comprehensive auto-mounting capabilities for production environments.

## Features

- **🔄 Automatic USB Detection**: Real-time monitoring and detection of USB devices
- **🗂️ Smart File Management**: Automatic copying of G-code files with duplicate handling
- **⚙️ Enterprise Auto-mounting**: Integrated pmount + systemd architecture for reliable USB mounting
- **📊 Dedicated Logging**: Separate USB activity logging to `~/.octoprint/logs/usbfilewatcher-usb.log`
- **🔧 Multiple Mount Points**: Supports up to 4 concurrent USB devices (`/media/usb1-4`)
- **🔒 Safe Unmounting**: Automatic unmounting after file operations with configurable delays
- **🐧 Linux Optimized**: Designed for Raspberry Pi and Linux-based 3D printer systems
- **📱 Web Interface**: Easy monitoring and control through OctoPrint's web interface

## Installation

### Plugin Installation

Install via the bundled [Plugin Manager](https://github.com/foosel/OctoPrint/wiki/Plugin:-Plugin-Manager)
or manually using this URL:

    https://github.com/MakerGear/OctoPrint-usbFileWatcher/archive/refs/heads/installer.zip

### Enterprise Deployment (Recommended)

For production 3D printer fleets, use the enterprise deployment package:

```bash
# Download the repository
git clone https://github.com/Garr-Garr/OctoPrint-usbFileWatcher.git
cd OctoPrint-usbFileWatcher/deployment

# Run enterprise installation (requires root)
sudo ./install.sh
```

This installs:
- System-level USB auto-mounting with pmount
- systemd services for device management
- udev rules for automatic detection
- Enterprise plugin configuration

## How It Works

### Basic Operation
1. **USB Device Inserted** → Automatic detection via udev rules
2. **Device Mounting** → pmount safely mounts to `/media/usb1-4`
3. **File Discovery** → Plugin scans for G-code files (`.gcode`, `.gco`, `.g`)
4. **Smart Copying** → Files copied to OctoPrint uploads with duplicate detection
5. **File Management** → Original files renamed with "COPIED" prefix
6. **Auto Unmount** → Device safely unmounted after configurable delay
7. **UI Refresh** → OctoPrint file list automatically updated

### File Handling
- **New files**: Copied directly to OctoPrint uploads folder
- **Duplicates with same content**: Skipped (no unnecessary copying)
- **Duplicates with different content**: Copied with timestamp suffix
- **Hash verification**: MD5 checking ensures file integrity
- **Original preservation**: Source files prefixed with "COPIED" after processing

### Enterprise Architecture
- **pmount/pumount**: Safe mounting without root privileges in operation
- **systemd services**: Hardware-level USB device lifecycle management
- **udev integration**: Kernel-level device detection and triggering
- **Multiple mount points**: Concurrent USB device support
- **Dedicated logging**: Separate log streams for troubleshooting

## Configuration

### Plugin Settings
Access via **OctoPrint Settings → Plugins → USB File Watcher**

**Basic Settings:**
- **Watch Folders**: Directories to monitor for files (default: `/media/usb1-4`)
- **Copy Destination**: Where files are copied (default: `~/.octoprint/uploads/USB`)
- **File Extensions**: Types of files to copy (default: `.gcode`, `.gco`, `.g`)
- **Auto Monitor**: Enable automatic USB device monitoring

**Enterprise Settings:**
- **Enterprise Mode**: Enable auto-mounting and advanced features
- **Auto Unmount**: Automatically unmount devices after copying
- **Unmount Delay**: Seconds to wait before unmounting (default: 30)
- **Debug Logging**: Enable detailed logging for troubleshooting

### Manual USB Setup (Alternative)

If not using enterprise deployment, configure manual USB mounting:

#### Prerequisites
```bash
# Install required packages
sudo apt-get update
sudo apt-get install pmount ntfs-3g exfat-fuse exfat-utils dosfstools

# Create mount points
sudo mkdir -p /media/usb{1,2,3,4}
```

#### Basic udev Rule
Create `/etc/udev/rules.d/99-usb-gcode.rules`:
```bash
# USB GCode Auto-mount
ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k.service"
ACTION=="remove", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k.service"
```

## Requirements

- **OctoPrint**: 1.4.0+ (Python 3.7+ compatible)
- **Operating System**: Linux (tested on Raspberry Pi OS)
- **Python**: 3.7 - 3.13.7 (fully compatible)
- **System Packages**: `pmount`, `ntfs-3g` (for NTFS support)
- **Permissions**: Sudo access for enterprise installation

### Supported Filesystems
- **FAT32/FAT16**: Native support
- **exFAT**: Via `exfat-fuse` package
- **NTFS**: Via `ntfs-3g` package
- **ext2/ext3/ext4**: Native Linux support

## Troubleshooting

### Check Plugin Status
```bash
# Plugin logs
tail -f ~/.octoprint/logs/usbfilewatcher-usb.log

# System USB events
sudo udevadm monitor --property --subsystem-match=block

# Mount status
mount | grep /media/usb
sudo pmount --list
```

### Common Issues

**USB not detected:**
- Verify udev rules: `sudo udevadm control --reload-rules`
- Check systemd services: `sudo systemctl status usbstick-handler@*`

**Files not copying:**
- Check mount permissions: `ls -la /media/usb*`
- Verify file extensions in plugin settings
- Review plugin logs for errors

**Mount failures:**
- Install filesystem support: `sudo apt-get install ntfs-3g exfat-fuse`
- Check disk health: `sudo fsck /dev/sdX1`

### Enterprise Support
For production deployments, see `deployment/README.md` for comprehensive setup instructions and troubleshooting.

## Development

This plugin is maintained by [MakerGear](https://github.com/MakerGear) for use in production 3D printer environments.

**Contributing:**
- Report issues via GitHub Issues
- Submit pull requests for improvements
- Follow OctoPrint plugin development guidelines

**License:** AGPLv3
