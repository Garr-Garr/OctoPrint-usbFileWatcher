#!/bin/bash
# USB GCode Transfer Setup Script
# Run this script when building your company image

set -e

echo "Setting up USB GCode Transfer system..."

# Create necessary directories
mkdir -p /usr/local/bin
mkdir -p /etc/udev/rules.d

# Copy scripts
cp usb-gcode-mount.sh /usr/local/bin/
cp usb-gcode-unmount.sh /usr/local/bin/
chmod +x /usr/local/bin/usb-gcode-*.sh

# Copy udev rules
cp 99-usb-gcode.rules /etc/udev/rules.d/

# Create log file with proper permissions
touch /var/log/usb-gcode.log
chown pi:pi /var/log/usb-gcode.log

# Add pi user to sudo for specific commands (if not already done)
echo "pi ALL=(ALL) NOPASSWD: /usr/local/bin/usb-gcode-mount.sh, /usr/local/bin/usb-gcode-unmount.sh" > /etc/sudoers.d/usb-gcode

# Reload udev rules
udevadm control --reload-rules

# Find USB port info (for documentation)
echo ""
echo "=== USB Port Information ==="
echo "To find your specific USB port, run:"
echo "  udevadm info --name=/dev/sda --attribute-walk | grep KERNELS"
echo ""
echo "Then update the KERNELS value in /etc/udev/rules.d/99-usb-gcode.rules"
echo ""
echo "Current USB devices:"
lsusb || true

echo ""
echo "Setup complete! Reboot to activate USB auto-mounting."
