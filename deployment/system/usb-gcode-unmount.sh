#!/bin/bash
# USB GCode Unmount Script using pumount (enterprise approach)
# Based on original systemd service design

DEVICE="$1"
LOG_FILE="/var/log/usb-gcode.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [UNMOUNT] $1" >> "$LOG_FILE"
}

# If no device specified, try to find mounted USB devices
if [ -z "$DEVICE" ]; then
    # Find mounted USB devices in /media/usb*
    for mount in /media/usb1 /media/usb2 /media/usb3 /media/usb4; do
        if mountpoint -q "$mount"; then
            DEVICE=$(basename "$mount")
            break
        fi
    done

    if [ -z "$DEVICE" ]; then
        log_message "No mounted USB devices found to unmount"
        exit 0
    fi
fi

# Use pumount to safely unmount (handles sync automatically)
if /usr/bin/pumount "/dev/$DEVICE" 2>/dev/null; then
    log_message "Successfully unmounted /dev/$DEVICE using pumount"

    # Clean up notification file
    rm -f /tmp/usb-gcode-mounted

    log_message "USB device $DEVICE safely removed"
else
    log_message "Failed to unmount /dev/$DEVICE with pumount, trying fallback"

    # Fallback: try to unmount mount points directly
    for mount in /media/usb1 /media/usb2 /media/usb3 /media/usb4; do
        if mountpoint -q "$mount"; then
            sync
            if umount "$mount" 2>/dev/null; then
                log_message "Fallback unmount successful for $mount"
            else
                # Force unmount as last resort
                umount -l "$mount" 2>/dev/null || true
                log_message "Forced lazy unmount of $mount"
            fi
        fi
    done
fi
