# USB File Watcher System - Manual Installation Guide

This guide provides step-by-step instructions for manually installing the USB auto-mounting system with comprehensive filesystem support.

## Prerequisites

- Raspberry Pi or Linux system running OctoPrint
- Root/sudo access
- USB File Watcher plugin installed in OctoPrint
- Internet connection for package installation

## Step 0: Install Required Packages

```bash
# Update package list
sudo apt-get update

# Install filesystem support packages
sudo apt-get install -y pmount ntfs-3g exfat-fuse exfat-utils dosfstools

# Verify installations
dpkg -l | grep -E "(pmount|ntfs-3g|exfat)"
```

## Step 1: Install System Scripts

```bash
# Create directories
sudo mkdir -p /usr/local/bin
sudo mkdir -p /etc/udev/rules.d
sudo mkdir -p /etc/sudoers.d
sudo mkdir -p /etc/systemd/system

# Copy mount script
sudo cp system/usb-gcode-mount.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/usb-gcode-mount.sh

# Copy unmount script
sudo cp system/usb-gcode-unmount.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/usb-gcode-unmount.sh

# Copy systemd service template
sudo cp system/usbstick-handler@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

## Step 2: Configure udev Rules

```bash
# Copy udev rules
sudo cp system/99-usb-gcode.rules /etc/udev/rules.d/

# Create mount points for multiple USB devices
sudo mkdir -p /media/usb{1,2,3,4}
sudo chown pi:pi /media/usb{1,2,3,4}

# Optional: Find your USB port identifier for specific port targeting
# Insert a USB device and run:
udevadm info --name=/dev/sda --attribute-walk | grep KERNELS

# Edit the rules file if you want to target a specific USB port
# sudo nano /etc/udev/rules.d/99-usb-gcode.rules
# Replace generic rule with specific KERNELS value if needed

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Step 3: Configure Sudo Permissions

```bash
# Copy sudo configuration
sudo cp system/usb-gcode-sudoers /etc/sudoers.d/usb-gcode
sudo chmod 440 /etc/sudoers.d/usb-gcode

# Test sudo configuration
sudo -u pi sudo -l | grep usb-gcode
```

## Step 4: Create Log File and Set Permissions

```bash
# Create log file with proper permissions
sudo touch /var/log/usb-gcode.log
sudo chown pi:pi /var/log/usb-gcode.log
sudo chmod 644 /var/log/usb-gcode.log

# Ensure mount points have proper permissions
sudo chown pi:pi /media/usb{1,2,3,4}
sudo chmod 755 /media/usb{1,2,3,4}

# Test pmount functionality
pmount --help > /dev/null && echo "pmount available" || echo "pmount not installed"
```

## Step 5: Configure OctoPrint Plugin

1. Open OctoPrint web interface
2. Go to Settings → Plugin Manager → USB File Watcher
3. Configure these settings:

```
Watch Folders:
/media/usb1
/media/usb2
/media/usb3
/media/usb4

Copy Destination: ~/.octoprint/uploads/USB
File Extensions: .gcode,.gco,.g,.stl
Auto Monitor: Enabled
Monitor Interval: 5 seconds
Enterprise Mode: Enabled
Auto Unmount: Enabled
Unmount Delay: 30 seconds
Debug Logging: Disabled (enable for troubleshooting)
```

4. Save settings and restart OctoPrint

## Step 6: Test Filesystem Support

```bash
# Test different filesystem support
echo "Testing filesystem support..."

# Check NTFS support
modinfo ntfs >/dev/null 2>&1 && echo "✓ NTFS support available" || echo "✗ NTFS support missing"

# Check exFAT support
modinfo exfat >/dev/null 2>&1 && echo "✓ exFAT support available" || echo "✗ exFAT support missing"

# Check FAT support (should be built-in)
modinfo vfat >/dev/null 2>&1 && echo "✓ FAT32 support available" || echo "✗ FAT32 support missing"

# Test pmount with different mount points
for i in {1..4}; do
    mountpoint -q /media/usb$i || echo "Mount point /media/usb$i ready"
done
```

## Step 7: Test Installation

```bash
# Run test script
chmod +x test/test-usb-system.sh
./test/test-usb-system.sh

# Manual test - insert USB device and check logs
tail -f /var/log/usb-gcode.log &

# Check plugin logs
tail -f ~/.octoprint/logs/usbfilewatcher-usb.log &

# Test systemd service
sudo systemctl status usbstick-handler@sda1.service

# Monitor udev events
sudo udevadm monitor --property --subsystem-match=block
```

## Step 8: Verify Operation with Different Filesystems

### Test FAT32 USB Drive
1. Insert FAT32 formatted USB device with GCode files
2. Check auto-mount: `mount | grep /media/usb`
3. Verify files copied to OctoPrint uploads
4. Confirm auto-unmount after delay

### Test NTFS USB Drive (Windows formatted)
1. Insert NTFS USB device
2. Verify NTFS mounting: `mount | grep ntfs`
3. Check file copying works correctly
4. Test unmounting: `sudo pumount /media/usb1`

### Test exFAT USB Drive (modern large drives)
1. Insert exFAT formatted device
2. Verify exFAT support: `mount | grep exfat`
3. Test large file handling
4. Verify safe unmounting

## Troubleshooting

## Troubleshooting

### USB Device Not Detected
- Verify udev rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`
- Check systemd services: `sudo systemctl status usbstick-handler@*`
- Monitor real-time events: `sudo udevadm monitor --property --subsystem-match=block`
- Test with different USB devices and ports

### Mount Permission Issues
- Verify sudo configuration: `sudo -u pi sudo -l | grep usb-gcode`
- Check mount script permissions: `ls -la /usr/local/bin/usb-gcode-*`
- Test manual mount: `sudo /usr/local/bin/usb-gcode-mount.sh sda1`
- Verify pmount installation: `which pmount && pmount --help`

### Filesystem Support Issues
```bash
# Check NTFS support
sudo mount -t ntfs /dev/sda1 /mnt/test 2>&1 || echo "NTFS support issue"

# Check exFAT support
sudo mount -t exfat /dev/sda1 /mnt/test 2>&1 || echo "exFAT support issue"

# Reinstall filesystem packages if needed
sudo apt-get install --reinstall ntfs-3g exfat-fuse exfat-utils dosfstools
```

### Plugin Not Responding
- Check OctoPrint plugin is enabled and named "USB File Watcher"
- Verify plugin settings match enterprise configuration
- Review plugin logs: `tail -f ~/.octoprint/logs/usbfilewatcher-usb.log`
- Restart OctoPrint service: `sudo systemctl restart octoprint`
- Check API endpoint: `curl -s "http://localhost:5000/api/plugin/usbfilewatcher"`

### Files Not Copying
- Ensure USB device has supported file types (`.gcode`, `.gco`, `.g`, `.stl`)
- Check destination folder permissions: `ls -la ~/.octoprint/uploads/USB`
- Verify mount point accessibility: `sudo -u pi ls -la /media/usb1`
- Review plugin logs for copy errors
- Test with smaller files first

### Multiple Device Issues
```bash
# Check all mount points
for i in {1..4}; do
    echo "Checking /media/usb$i:"
    mountpoint /media/usb$i && ls -la /media/usb$i || echo "Not mounted"
done

# Test pmount with specific device
sudo pmount /dev/sdb1 usb2  # Mount second device to usb2
```

### systemd Service Issues
```bash
# Check service status
sudo systemctl status usbstick-handler@*.service

# View service logs
sudo journalctl -u usbstick-handler@sda1.service -f

# Manually start service for testing
sudo systemctl start usbstick-handler@sda1.service
```

## Uninstalling

```bash
# Remove system files
sudo rm -f /usr/local/bin/usb-gcode-*.sh
sudo rm -f /etc/udev/rules.d/99-usb-gcode.rules
sudo rm -f /etc/sudoers.d/usb-gcode
sudo rm -f /etc/systemd/system/usbstick-handler@.service

# Clean up mount points
sudo rmdir /media/usb{1,2,3,4} 2>/dev/null || true

# Remove log files
sudo rm -f /var/log/usb-gcode.log

# Reload system services
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger

# Optional: Remove filesystem packages (only if not needed elsewhere)
# sudo apt-get remove ntfs-3g exfat-fuse exfat-utils
```

## Advanced Configuration

### Custom Mount Points
To use different mount points, edit the mount script:
```bash
sudo nano /usr/local/bin/usb-gcode-mount.sh
# Modify MOUNT_POINT selection logic
```

### Filesystem-Specific Options
For specific filesystem mounting options:
```bash
sudo nano /usr/local/bin/usb-gcode-mount.sh
# Add filesystem-specific pmount options:
# --umask 022 for FAT filesystems
# --iocharset=utf8 for NTFS
```

### USB Port Restrictions
To limit to specific USB ports, edit udev rules:
```bash
sudo nano /etc/udev/rules.d/99-usb-gcode.rules
# Add KERNELS=="1-1.4" to restrict to specific port
```

This manual installation provides comprehensive USB file management with full filesystem support for enterprise 3D printing environments.
