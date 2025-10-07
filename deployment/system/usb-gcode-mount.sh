#!/bin/bash
# USB GCode Mount Script using pmount (enterprise approach)
# Based on original cpmount design

DEVICE="/dev/$1"
LOG_FILE="/var/log/usb-gcode.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [MOUNT] $1" >> "$LOG_FILE"
}

# Check if device exists
if [ ! -b "$DEVICE" ]; then
    log_message "Device $DEVICE does not exist"
    exit 1
fi

# Find available mount point (similar to original cpmount logic)
if mountpoint -q /media/usb1
then
   if mountpoint -q /media/usb2
   then
      if mountpoint -q /media/usb3
      then
         if mountpoint -q /media/usb4
         then
             log_message "No mountpoints available!"
             exit 1
         else
             MOUNT_POINT="usb4"
         fi
      else
         MOUNT_POINT="usb3"
      fi
   else
      MOUNT_POINT="usb2"
   fi
else
   MOUNT_POINT="usb1"
fi

# Mount using pmount with same options as original
if /usr/bin/pmount --umask 000 --noatime -w --sync "$DEVICE" "$MOUNT_POINT"; then
    log_message "Successfully mounted $DEVICE to /media/$MOUNT_POINT using pmount"

    # Trigger OctoPrint plugin scan (using API like original)
    sudo -u pi /home/pi/oprint/bin/octoprint client get '/api/plugin/usbfilewatcher' 2>/dev/null || \
    curl -s "http://localhost:5000/api/plugin/usbfilewatcher" 2>/dev/null || \
    touch /tmp/usb-gcode-mounted  # Fallback notification

    log_message "USB device $MOUNT_POINT ready for file transfer"
else
    log_message "Failed to mount $DEVICE using pmount"
    exit 1
fi
