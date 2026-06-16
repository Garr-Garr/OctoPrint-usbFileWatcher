# OctoPrint-usbFileWatcher

USB File Watcher is an OctoPrint plugin that automatically detects USB drives, mounts them, finds print files, and copies them where OctoPrint can use them. It started as a simple flash drive helper and grew into a solid auto-mount setup that works well on production machines.

## Features

- **Automatic USB detection**: Watches for USB device insert/remove events in real time.
- **Smart file handling**: Copies G-code files and handles duplicates safely.
- **Auto-mount support**: Uses a `pmount` + `systemd` setup for reliable mounting.
- **Dedicated logs**: USB activity is logged separately in `~/.octoprint/logs/usbfilewatcher-usb.log`.
- **Multiple mount points**: Supports up to four USB devices at once (`/media/usb1-4`).
- **Safe unmounting**: Can unmount automatically after file operations with a configurable delay.
- **Linux-focused**: Built for Raspberry Pi and other Linux-based OctoPrint systems.
- **Web UI integration**: Configure and monitor behavior from the OctoPrint interface.

## Installation

### Plugin Installation

Install from the built-in [Plugin Manager](https://github.com/foosel/OctoPrint/wiki/Plugin:-Plugin-Manager),
or install manually from this URL:

    https://github.com/Garr-Garr/OctoPrint-usbFileWatcher/archive/refs/heads/installer.zip

### Enterprise Deployment (Recommended)

If you're deploying this across production printers, use the deployment package:

```bash
# Download the repository
git clone https://github.com/Garr-Garr/OctoPrint-usbFileWatcher.git
cd OctoPrint-usbFileWatcher/deployment

# Run installation (requires root)
sudo ./install.sh
```

This installs:
- System-level USB auto-mounting with `pmount`
- `systemd` services for USB handling
- `udev` rules for automatic device detection
- Plugin settings tuned for this setup

## How It Works

### Basic Operation
1. **USB inserted**: `udev` catches the event.
2. **Drive mounted**: `pmount` mounts it to `/media/usb1-4`.
3. **Files scanned**: The plugin looks for `.gcode`, `.gco`, and `.g` files.
4. **Files copied**: Files are copied to OctoPrint uploads with duplicate checks.
5. **Original marked**: Source files are renamed with a `COPIED` prefix.
6. **Drive unmounted**: It unmounts after a configurable delay.
7. **UI updated**: OctoPrint refreshes the file list.

### File Handling
- **New files**: Copied directly to the OctoPrint uploads folder.
- **Duplicate name, same content**: Skipped.
- **Duplicate name, different content**: Copied with a timestamp suffix.
- **Integrity check**: MD5 hashes are used to confirm file content.
- **Source tracking**: Original files are prefixed with `COPIED` after processing.

### Enterprise Architecture
- **`pmount`/`pumount`**: Safer mount handling during normal operation.
- **`systemd` services**: Manages USB device lifecycle events.
- **`udev` integration**: Triggers mount/unmount flow at the kernel event level.
- **Multiple mount points**: Supports concurrent USB devices.
- **Dedicated logging**: Keeps USB activity in its own log stream.

## Configuration

### Plugin Settings
Access via **OctoPrint Settings → Plugins → USB File Watcher**

**Basic Settings:**
- **Watch Folders**: Folders to scan (default: `/media/usb1-4`)
- **Copy Destination**: Where files are copied (default: `~/.octoprint/uploads/USB`)
- **File Extensions**: Allowed extensions (default: `.gcode`, `.gco`, `.g`)
- **Auto Monitor**: Turns on automatic USB monitoring

**Enterprise Settings:**
- **Enterprise Mode**: Enables auto-mounting and advanced behavior
- **Auto Unmount**: Unmounts devices after copy operations
- **Unmount Delay**: Delay in seconds before unmount (default: 30)
- **Debug Logging**: Adds extra logging for troubleshooting

### Manual USB Setup (Alternative)

If you are not using the deployment package, you can still set this up manually:

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
- **Python**: 3.7 to 3.13.7
- **System Packages**: `pmount`, `ntfs-3g` (for NTFS support)
- **Permissions**: `sudo` access for deployment install

### Supported Filesystems
- **FAT32/FAT16**: Native support
- **exFAT**: Via `exfat-fuse`
- **NTFS**: Via `ntfs-3g`
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
For production deployments, check `deployment/README.md` for full setup and troubleshooting steps.

## Development

This plugin is maintained by Garrett @[MakerGear](https://github.com/MakerGear) and used in production 3D printer environments.

**Contributing:**
- Report issues via GitHub Issues
- Submit pull requests for improvements
- Follow OctoPrint plugin development guidelines

**License:** AGPLv3
