# coding=utf-8
from __future__ import absolute_import

import octoprint.plugin
import os
import sys
import shutil
import hashlib
import flask
import datetime
import time
import threading
import glob
import logging
import logging.handlers
from octoprint.events import Events


class UsbfilewatcherPlugin(octoprint.plugin.SettingsPlugin,
						   octoprint.plugin.AssetPlugin,
						   octoprint.plugin.TemplatePlugin,
						   octoprint.plugin.SimpleApiPlugin,
						   octoprint.plugin.EventHandlerPlugin,
						   octoprint.plugin.StartupPlugin):

	def __init__(self):
		self._usb_monitor_thread = None
		self._stop_monitoring = False
		self._usb_logger = None

	def on_startup(self, host, port):
		"""Setup dedicated logger for USB FileMan plugin"""
		try:
			self._usb_logger = self._logger

			# Setup our custom logger
			usb_logging_handler = logging.handlers.RotatingFileHandler(
				self._settings.get_plugin_logfile_path(postfix="usb"),
				maxBytes=2*1024*1024
			)
			usb_logging_handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
			usb_logging_handler.setLevel(logging.DEBUG)

			self._usb_logger.addHandler(usb_logging_handler)
			self._usb_logger.setLevel(logging.DEBUG if self._settings.get_boolean(["debug_logging"]) else logging.INFO)
			self._usb_logger.propagate = False

			self._safe_log("info", "=== USB File Watcher Plugin Logger Started ===")
		except Exception as e:
			# Fallback to regular logger if dedicated logger setup fails
			self._usb_logger = self._logger
			self._logger.error(f"Failed to setup dedicated USB logger: {e}")

	def _safe_log(self, level, message):
		"""Safely log to USB logger with fallback"""
		try:
			if hasattr(self, '_usb_logger') and self._usb_logger:
				getattr(self._usb_logger, level)(message)
			else:
				# Fallback to regular logger
				getattr(self._logger, level)(message)
		except Exception:
			# Last resort - use print for critical errors
			print(f"USB File Watcher {level.upper()}: {message}")

	##~~ SettingsPlugin mixin

	def get_settings_defaults(self):
		return dict(
			# Basic Settings
			watchFolders=[
				"/media/usb1",
				"/media/usb2",
				"/media/usb3",
				"/media/usb4"
			],
			enabled=True,
			autoMonitor=True,
			monitorInterval=5,  # seconds between USB checks
			copyFolder="~/.octoprint/uploads/USB",

			# Enterprise Features
			enterpriseMode=True,
			autoUnmount=True,
			unmountDelay=30,  # seconds

			# File Management
			extensions=[".gcode", ".gco", ".g"],
			copyFileTypes=[".gcode", ".gco", ".g"],  # alias for backwards compatibility
			fileAction="rename",  # "rename" or "delete"
			deleteAfterCopy=False,
			overwriteExisting=False,

			# Advanced Options
			logLevel="INFO",
			debug_logging=False
		)

	def on_after_startup(self):
		"""Initialize USB folder and start monitoring"""
		self._setup_usb_folder()

		# Start USB monitoring thread
		if self._settings.get_boolean(["autoMonitor"]):
			self.start_usb_monitoring()

		# Trigger a file list refresh to make the USB folder visible immediately
		try:
			self._event_bus.fire(Events.UPDATED_FILES, dict(type="printables"))
		except Exception as e:
			self._safe_log("debug", f"Could not trigger file list refresh: {e}")

		self._safe_log("info", "USB File Watcher plugin started successfully")

	def _setup_usb_folder(self):
		"""Setup USB folder only if it doesn't exist or path has changed"""
		try:
			target_usb_folder = self._ensure_usb_upload_folder()
			if target_usb_folder:
				self._usb_logger.info(f"USB upload folder ready: {target_usb_folder}")

		except Exception as e:
			self._usb_logger.error(f"Exception while setting up USB folder: {e}")
			# Final fallback
			try:
				fallback_path = os.path.expanduser("~/.octoprint/uploads/USB")
				os.makedirs(fallback_path, exist_ok=True)
				self._settings.set(["copyFolder"], fallback_path)
				self._settings.save()
				self._usb_logger.info(f"Created fallback USB folder: {fallback_path}")
			except Exception as fallback_error:
				self._usb_logger.error(f"Failed to create any USB folder: {fallback_error}")

	def _ensure_usb_upload_folder(self):
		"""Resolve/create the OctoPrint uploads USB folder and keep settings aligned."""
		copy_folder = self._settings.get(["copyFolder"]) or "~/.octoprint/uploads/USB"
		if copy_folder.startswith('~'):
			copy_folder = os.path.expanduser(copy_folder)

		# Prefer OctoPrint's local uploads path when available.
		target_usb_folder = copy_folder
		try:
			uploads_path = self._file_manager.path_on_disk("local", "")
			target_usb_folder = os.path.join(uploads_path, "USB")
		except Exception:
			pass

		os.makedirs(target_usb_folder, exist_ok=True)

		if copy_folder != target_usb_folder:
			self._settings.set(["copyFolder"], target_usb_folder)
			self._settings.save()
			self._safe_log("info", f"Updated USB folder path to: {target_usb_folder}")

		return target_usb_folder

	def start_usb_monitoring(self):
		"""Start monitoring for USB devices"""
		if self._usb_monitor_thread is None or not self._usb_monitor_thread.is_alive():
			self._stop_monitoring = False
			self._usb_monitor_thread = threading.Thread(target=self._monitor_usb_devices)
			self._usb_monitor_thread.daemon = True
			self._usb_monitor_thread.start()
			self._safe_log("info", "USB monitoring started")

	def stop_usb_monitoring(self):
		"""Stop monitoring for USB devices"""
		self._stop_monitoring = True
		if self._usb_monitor_thread and self._usb_monitor_thread.is_alive():
			self._usb_monitor_thread.join(timeout=5)
		self._safe_log("info", "USB monitoring stopped")

	def _monitor_usb_devices(self):
		"""Monitor for USB devices and automatically copy files - Enterprise mode"""
		last_devices = set()

		# Check platform once at the start
		is_linux = sys.platform.startswith('linux')
		if not is_linux:
			self._safe_log("info", "Non-Linux system detected. Only monitoring configured watch folders.")

		self._safe_log("info", "Starting USB device monitoring loop (Enterprise Mode)")

		# Monitor for auto-mount notification file if in enterprise mode
		enterprise_mode = self._settings.get_boolean(["enterpriseMode"])
		mount_notification_file = "/tmp/usb-gcode-mounted"

		while not self._stop_monitoring:
			try:
				current_devices = set()

				# Focus on Linux/Raspberry Pi USB mount points only
				if is_linux:
					# Check common Linux USB mount points
					for base_path in ['/media', '/mnt']:
						if os.path.exists(base_path):
							try:
								for item in os.listdir(base_path):
									full_path = os.path.join(base_path, item)
									if os.path.ismount(full_path) or os.path.isdir(full_path):
										current_devices.add(full_path)
										self._safe_log("debug", f"Found mount point: {full_path}")
							except (PermissionError, OSError) as e:
								self._safe_log("debug", f"Cannot access {base_path}: {e}")

				# Check for new USB devices
				new_devices = current_devices - last_devices
				if new_devices:
					self._safe_log("info", f"New USB device(s) detected: {new_devices}")
					# Small delay to ensure the device is fully mounted
					time.sleep(2)
					self._scan_and_copy_files()

				# Also log if devices were removed
				removed_devices = last_devices - current_devices
				if removed_devices:
					self._safe_log("info", f"USB device(s) removed: {removed_devices}")

				# Enterprise mode: Check for auto-mount notification
				if enterprise_mode and os.path.exists(mount_notification_file):
					self._safe_log("info", "Auto-mount notification detected, scanning for files...")
					self._scan_and_copy_files()
					# Remove notification file after processing
					try:
						os.remove(mount_notification_file)
					except OSError:
						pass

				last_devices = current_devices

				# Every few iterations, check for unmounted USB devices
				if hasattr(self, '_monitor_iteration'):
					self._monitor_iteration += 1
				else:
					self._monitor_iteration = 0

				# Check for unmounted devices every 10th iteration in enterprise mode
				check_interval = 10 if enterprise_mode else 5
				if self._monitor_iteration % check_interval == 0:
					self._check_for_new_usb_devices()

				time.sleep(self._settings.get_int(["monitorInterval"]) or 5)

			except Exception as e:
				self._safe_log("error", f"Error in USB monitoring: {e}")
				time.sleep(5)  # Wait longer on error

	def _get_usb_mount_points(self):
		"""Get list of USB mount points - Linux focused"""
		mount_points = []

		try:
			if sys.platform.startswith('linux'):
				# Linux/Raspberry Pi specific detection
				for base_path in ['/media', '/mnt']:
					if os.path.exists(base_path):
						try:
							for item in os.listdir(base_path):
								full_path = os.path.join(base_path, item)
								# Check if it's a directory and accessible
								if os.path.isdir(full_path):
									try:
										# Test if we can access the directory
										os.listdir(full_path)
										mount_points.append(full_path)
										self._safe_log("debug", f"Found mounted USB device: {full_path}")
										
										# Additional debugging for filesystem type
										try:
											import subprocess
											result = subprocess.run(['stat', '-f', '-c', '%T', full_path], 
																  capture_output=True, text=True, timeout=5)
											if result.returncode == 0:
												fs_type = result.stdout.strip()
												self._safe_log("debug", f"Filesystem type for {full_path}: {fs_type}")
										except Exception:
											pass  # Don't fail if we can't detect filesystem type
											
									except (PermissionError, OSError):
										pass  # Skip inaccessible directories
						except (PermissionError, OSError):
							pass

				# Also check for systemd automount points (common on newer Linux)
				if os.path.exists('/run/media'):
					try:
						for user_dir in os.listdir('/run/media'):
							user_path = os.path.join('/run/media', user_dir)
							if os.path.isdir(user_path):
								for device in os.listdir(user_path):
									device_path = os.path.join(user_path, device)
									if os.path.isdir(device_path):
										mount_points.append(device_path)
										self._safe_log("debug", f"Found systemd mounted USB device: {device_path}")
					except (PermissionError, OSError):
						pass

			else:
				self._safe_log("info", "Non-Linux system: Skipping automatic USB detection")
		except Exception as e:
			self._safe_log("error", f"Error getting USB mount points: {e}")

		# Always check configured watch folders (works on all platforms)
		for folder in self._settings.get(["watchFolders"]) or []:
			if os.path.exists(folder) and folder not in mount_points:
				mount_points.append(folder)

		if not mount_points:
			self._safe_log("debug", "No USB mount points found. Check if USB devices are mounted.")
		else:
			self._safe_log("info", f"Total mount points found: {len(mount_points)} - {mount_points}")

		return mount_points

	def _run_diagnostics(self):
		"""Run comprehensive diagnostics for USB filesystem support"""
		diagnostics = {
			"timestamp": datetime.datetime.now().isoformat(),
			"platform": sys.platform,
			"packages": {},
			"filesystem_support": {},
			"usb_devices": {},
			"mount_points": {},
			"logs": {}
		}
		
		try:
			# Check required packages
			import subprocess
			packages_to_check = ["pmount", "exfat-fuse", "exfat-utils", "ntfs-3g", "dosfstools"]
			
			for package in packages_to_check:
				try:
					result = subprocess.run(['dpkg', '-l', package], 
											capture_output=True, text=True, timeout=5)
					diagnostics["packages"][package] = "installed" if result.returncode == 0 else "not_installed"
				except Exception:
					diagnostics["packages"][package] = "unknown"
			
			# Check filesystem support
			fs_commands = {
				"exfat": "mount.exfat",
				"ntfs": "mount.ntfs-3g", 
				"vfat": "mount.vfat"
			}
			
			for fs_type, command in fs_commands.items():
				try:
					result = subprocess.run(['which', command], 
											capture_output=True, text=True, timeout=5)
					diagnostics["filesystem_support"][fs_type] = "available" if result.returncode == 0 else "not_available"
				except Exception:
					diagnostics["filesystem_support"][fs_type] = "unknown"
			
			# Check USB devices and their filesystems
			try:
				result = subprocess.run(['lsblk', '-J', '-o', 'NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT'], 
										capture_output=True, text=True, timeout=10)
				if result.returncode == 0:
					import json
					lsblk_data = json.loads(result.stdout)
					
					usb_devices = []
					for device in lsblk_data.get('blockdevices', []):
						if device.get('children'):
							for child in device.get('children', []):
								if child.get('fstype'):
									usb_devices.append({
										"device": f"/dev/{child.get('name')}",
										"filesystem": child.get('fstype'),
										"size": child.get('size'),
										"mountpoint": child.get('mountpoints', [None])[0] if child.get('mountpoints') else None
									})
					
					diagnostics["usb_devices"]["detected"] = usb_devices
				else:
					diagnostics["usb_devices"]["error"] = "Could not run lsblk"
			except Exception as e:
				diagnostics["usb_devices"]["error"] = str(e)
			
			# Check mount points
			for mount_path in ["/media/usb1", "/media/usb2", "/media/usb3", "/media/usb4"]:
				mount_info = {
					"exists": os.path.exists(mount_path),
					"is_mount": False,
					"filesystem": None,
					"device": None
				}
				
				if os.path.exists(mount_path):
					try:
						mount_info["is_mount"] = os.path.ismount(mount_path)
						if mount_info["is_mount"]:
							# Get filesystem info
							result = subprocess.run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE', mount_path], 
													capture_output=True, text=True, timeout=5)
							if result.returncode == 0:
								parts = result.stdout.strip().split()
								if len(parts) >= 2:
									mount_info["device"] = parts[0]
									mount_info["filesystem"] = parts[1]
					except Exception:
						pass
				
				diagnostics["mount_points"][mount_path] = mount_info
			
			# Get recent log entries
			try:
				if hasattr(self, '_usb_logger') and self._usb_logger:
					# Get recent log messages (this is a simplified approach)
					diagnostics["logs"]["plugin_status"] = "logger_active"
				else:
					diagnostics["logs"]["plugin_status"] = "logger_inactive"
			except Exception:
				diagnostics["logs"]["plugin_status"] = "unknown"
			
			self._safe_log("info", f"Diagnostics completed: {len(diagnostics)} categories checked")
			
		except Exception as e:
			diagnostics["error"] = str(e)
			self._safe_log("error", f"Error running diagnostics: {e}")
		
		return diagnostics

	def _check_for_new_usb_devices(self):
		"""Check for new USB devices that might need mounting (enterprise mode)"""
		if not self._settings.get_boolean(["enterpriseMode"]):
			return

		try:
			# This is a placeholder for enterprise auto-mounting logic
			# In a real deployment, this would check for unmounted USB devices
			# and trigger the systemd auto-mount services
			self._safe_log("debug", "Checking for new USB devices...")
		except Exception as e:
			self._safe_log("debug", f"Error checking for new USB devices: {e}")

	def _check_and_mount_usb_devices(self):
		"""Enterprise mode: Automatically mount detected USB devices"""
		if not self._settings.get_boolean(["enterpriseMode"]):
			return

		try:
			import subprocess
			# Check for unmounted USB devices
			result = subprocess.run(['lsblk', '-J', '-o', 'NAME,SIZE,TYPE,MOUNTPOINTS'],
								  capture_output=True, text=True, timeout=10)

			if result.returncode == 0:
				import json
				lsblk_data = json.loads(result.stdout)

				for device in lsblk_data.get('blockdevices', []):
					if device.get('type') == 'disk':
						for child in device.get('children', []):
							if (child.get('type') == 'part' and
								(not child.get('mountpoints') or child.get('mountpoints') == [None])):
								device_name = f"/dev/{child.get('name')}"

								# Auto-mount to our dedicated mount point
								mount_point = "/media/gcode-transfer"
								try:
									# Create mount point
									os.makedirs(mount_point, exist_ok=True)

									# Mount the device
									mount_result = subprocess.run([
										'sudo', 'mount', '-o', 'uid=pi,gid=pi,umask=0022',
										device_name, mount_point
									], capture_output=True, text=True, timeout=30)

									if mount_result.returncode == 0:
										self._usb_logger.info(f"Auto-mounted {device_name} to {mount_point}")
										# Trigger file scanning
										time.sleep(1)
										self._scan_and_copy_files()
									else:
										self._usb_logger.debug(f"Failed to mount {device_name}: {mount_result.stderr}")

								except Exception as e:
									self._usb_logger.debug(f"Error auto-mounting {device_name}: {e}")

		except Exception as e:
			self._usb_logger.debug(f"Error in auto-mount check: {e}")

	def _auto_unmount_after_copy(self, mount_point="/media/gcode-transfer"):
		"""Auto-unmount the USB device after copying files"""
		if not self._settings.get_boolean(["autoUnmount"]):
			return

		def delayed_unmount():
			delay = self._settings.get_int(["unmountDelay"]) or 30
			self._usb_logger.info(f"Auto-unmounting {mount_point} in {delay} seconds...")
			time.sleep(delay)

			try:
				import subprocess
				# Sync before unmounting
				subprocess.run(['sync'], timeout=10)

				# Unmount
				result = subprocess.run(['sudo', 'umount', mount_point],
									  capture_output=True, text=True, timeout=30)
				if result.returncode == 0:
					self._usb_logger.info(f"Successfully auto-unmounted {mount_point}")
					# Remove mount point
					try:
						os.rmdir(mount_point)
					except OSError:
						pass
				else:
					self._usb_logger.warning(f"Failed to auto-unmount {mount_point}: {result.stderr}")

			except Exception as e:
				self._usb_logger.error(f"Error during auto-unmount: {e}")

		# Run in background
		unmount_thread = threading.Thread(target=delayed_unmount)
		unmount_thread.daemon = True
		unmount_thread.start()

	def _scan_and_copy_files(self):
		"""Scan USB devices and copy files with auto-unmount support"""
		try:
			# Call the file copying logic directly without using Flask context
			result_message = self._copy_files_from_usb_direct()
			
			if "Copied" in result_message:
				# Safely fire event with proper context handling
				try:
					self._event_bus.fire(Events.UPDATED_FILES, dict(type="printables"))
				except Exception as e:
					self._safe_log("debug", f"Could not fire UPDATED_FILES event: {e}")

				# Auto-unmount if enabled and in enterprise mode
				if (self._settings.get_boolean(["autoUnmount"]) and
					self._settings.get_boolean(["enterpriseMode"])):
					self._schedule_auto_unmount()

		except Exception as e:
			self._safe_log("error", f"Error in auto file copy: {e}")

	def _schedule_auto_unmount(self):
		"""Schedule auto-unmount after file copying using pumount (enterprise approach)"""
		def delayed_unmount():
			delay = self._settings.get_int(["unmountDelay"]) or 30
			self._safe_log("info", f"Scheduling auto-unmount in {delay} seconds...")
			time.sleep(delay)

			# Find currently mounted USB devices in /media/usb*
			mounted_devices = []
			for mount_point in ["/media/usb1", "/media/usb2", "/media/usb3", "/media/usb4"]:
				if os.path.ismount(mount_point):
					mounted_devices.append(mount_point)

			if mounted_devices:
				for mount_point in mounted_devices:
					try:
						import subprocess
						# Use pumount (safer than direct umount)
						device_name = os.path.basename(mount_point)
						result = subprocess.run(['sudo', 'pumount', f'/dev/{device_name}'],
											  capture_output=True, text=True, timeout=30)
						if result.returncode == 0:
							self._safe_log("info", f"Auto-unmount completed successfully for {mount_point}")
						else:
							# Fallback to our unmount script
							result = subprocess.run(['sudo', '/usr/local/bin/usb-gcode-unmount.sh'],
												  capture_output=True, text=True, timeout=30)
							if result.returncode == 0:
								self._safe_log("info", "Auto-unmount completed using fallback script")
							else:
								self._safe_log("warning", f"Auto-unmount failed: {result.stderr}")
					except Exception as e:
						self._safe_log("error", f"Error during auto-unmount: {e}")
			else:
				self._safe_log("debug", "No mount points found, skipping auto-unmount")

		# Run unmount in background thread
		unmount_thread = threading.Thread(target=delayed_unmount)
		unmount_thread.daemon = True
		unmount_thread.start()

	def on_api_get(self, request):
		self._safe_log("info", "usbfilewatcher on_api_get triggered.  Request: "+str(request))
		return self._copy_files_from_usb()

	def _copy_files_from_usb(self):
		"""Copy files from USB devices to the copy folder - Flask API version"""
		result_message = self._copy_files_from_usb_direct()
		return flask.jsonify(result="Finished without error.  Results: "+result_message)

	def _copy_files_from_usb_direct(self):
		"""Copy files from USB devices to the copy folder - Direct version for background threads"""
		resultMessage = ""
		newFiles = False
		dest = self._settings.get(["copyFolder"])

		# Always resolve to OctoPrint's uploads/USB folder when possible.
		try:
			dest = self._ensure_usb_upload_folder()
		except Exception as e:
			self._safe_log("warning", f"Could not resolve USB upload folder via file manager: {e}")

		# Expand user path if it starts with ~
		if dest and dest.startswith('~'):
			dest = os.path.expanduser(dest)

		# Ensure destination directory exists
		if dest:
			try:
				os.makedirs(dest, exist_ok=True)
			except Exception as e:
				self._safe_log("error", f"Could not create destination directory {dest}: {e}")
				return f"Could not create destination directory {dest}: {e}"

		# Get USB mount points automatically
		usb_mount_points = self._get_usb_mount_points()

		# Also include configured watch folders
		all_folders_to_check = list(set((self._settings.get(["watchFolders"]) or []) + usb_mount_points))

		for folderToCheck in all_folders_to_check:
			src = folderToCheck
			if not os.path.exists(folderToCheck):
				resultMessage += f" --- USB mount path does not exist: {folderToCheck}"
				continue

			try:
				# More targeted file scanning - only look for gcode files
				file_paths = []
				max_files = 100  # Reduced limit since we're being more selective
				max_depth = 3    # Limit recursion depth
				valid_extensions = self._settings.get(["extensions"]) or [".gcode", ".gco", ".g"]
				
				# Debug: List what's actually in the root directory
				try:
					root_contents = os.listdir(src)
					# Filter to show only relevant files and directories
					relevant_items = []
					for item in root_contents:
						if not item.startswith('.') and not item.upper() in ['SYSTEM VOLUME INFORMATION', '$RECYCLE.BIN']:
							relevant_items.append(item)
					
					self._safe_log("info", f"Relevant items in {src}: {relevant_items[:10]}...")
					if len(relevant_items) > 10:
						self._safe_log("info", f"Total relevant items: {len(relevant_items)} (showing first 10)")
				except Exception as e:
					self._safe_log("warning", f"Could not list root contents of {src}: {e}")

				for root, dirs, files in os.walk(src):
					# Calculate current depth
					depth = root[len(src):].count(os.sep)
					if depth >= max_depth:
						dirs[:] = []  # Don't recurse deeper
						continue

					# Skip hidden directories and common system directories
					dirs[:] = [d for d in dirs if not d.startswith('.') and d.upper() not in ['SYSTEM VOLUME INFORMATION', '$RECYCLE.BIN', 'LOST+FOUND', 'RECYCLER']]
					
					# Only look at files that could be gcode files
					for file in files:
						# Quick extension check first (most efficient filter)
						_, file_ext = os.path.splitext(file)
						if file_ext.lower() not in valid_extensions:
							continue
							
						# Skip hidden files, system files, and common junk files
						if (file.startswith('.') or 
							file.startswith('~') or
							file.startswith('COPIED') or
							file.upper() in ['THUMBS.DB', 'DESKTOP.INI', '.DS_STORE'] or
							file.endswith('.tmp') or
							file.endswith('.log')):
							continue
							
						if len(file_paths) >= max_files:
							self._safe_log("warning", f"File limit reached ({max_files}) gcode files in {src}, stopping scan")
							break
						file_paths.append(os.path.join(root, file))

					if len(file_paths) >= max_files:
						break

				self._safe_log("info", f"Found {len(file_paths)} potential gcode files in {src} (max depth: {max_depth})")
				
				# Debug: Show the actual gcode files found
				if file_paths:
					gcode_files = [os.path.basename(f) for f in file_paths]
					self._safe_log("info", f"Gcode files found: {gcode_files}")
			except Exception as e:
				self._safe_log("info", "Could not list files in watchFolder; exception: "+str(e))
				resultMessage += f" --- Could not list files in watchFolder; exception: {e}"
				continue

			try:
				for full_src_name in file_paths:
					file_name = os.path.basename(full_src_name)
					file_root, file_extension = os.path.splitext(file_name)

					# More comprehensive filtering of unwanted files
					if str(file_root).startswith("COPIED"):
						self._safe_log("debug", "File already copied according to name: "+str(file_name))
						continue
					if str(file_root).startswith("._"):
						self._safe_log("debug", "File seems to be a Mac system file; skipping.  Filename : "+str(file_name))
						continue
					if file_name.upper() in ['THUMBS.DB', 'DESKTOP.INI', '.DS_STORE', 'AUTORUN.INF']:
						self._safe_log("debug", f"Skipping system file: {file_name}")
						continue
					if file_extension.lower() in ['.tmp', '.log', '.bak', '.old']:
						self._safe_log("debug", f"Skipping temporary/backup file: {file_name}")
						continue
						
					# Only process files with valid 3D printing extensions
					valid_extensions = self._settings.get(["extensions"]) or [".gcode", ".gco", ".g"]
					if file_extension.lower() in valid_extensions:
						full_dest_name = os.path.join(dest, file_name)

						if not os.path.isfile(full_dest_name):
							shutil.copy2(full_src_name, full_dest_name)
							self._safe_log("info", "Copied "+file_name+" to uploads/USB folder.")
							resultMessage += f" --- Copied {file_name} to uploads/USB folder."
							newFiles = True

							if (self._settings.get(["fileAction"]) or "rename") == "rename":
								copiedName = os.path.join(os.path.dirname(full_src_name), "COPIED" + file_name)
								os.rename(full_src_name, copiedName)
								resultMessage += f" --- Renamed original file in watchFolder to: {copiedName}"
						else:
							# Compare file hashes
							if self._get_file_hash(full_src_name) != self._get_file_hash(full_dest_name):
								timestamp = datetime.datetime.now().strftime('%y-%m-%d_%H-%M')
								newDestName = os.path.join(dest, f"{file_root}-{timestamp}{file_extension}")
								shutil.copy2(full_src_name, newDestName)
								self._safe_log("info", f"Copied a new version of {file_name} to uploads/USB folder as {newDestName}")
								resultMessage += f" --- Copied a new version of {file_name} to uploads/USB folder as {newDestName}"
								newFiles = True

								if (self._settings.get(["fileAction"]) or "rename") == "rename":
									copiedName = os.path.join(os.path.dirname(full_src_name), "COPIED" + file_name)
									os.rename(full_src_name, copiedName)
									resultMessage += f" --- Renamed original file in watchFolder to: {copiedName}"
					else:
						self._safe_log("debug", f"Skipping non-gcode file: {file_name} (extension: {file_extension})")
			except Exception as e:
				self._safe_log("info", "Could not copy files to uploads/USB folder; exception: "+str(e))
				resultMessage += f" --- Could not copy files to uploads/USB folder; exception: {e}"
				continue

		if resultMessage == "":
			resultMessage = "Nothing to do."
		
		if newFiles:
			try:
				self._event_bus.fire(Events.UPDATED_FILES, dict(type="printables"))
			except Exception as e:
				self._safe_log("debug", f"Could not fire UPDATED_FILES event: {e}")
		
		return resultMessage

	def _get_file_hash(self, filepath):
		"""Get MD5 hash of a file"""
		hash_md5 = hashlib.md5()
		try:
			with open(filepath, "rb") as f:
				for chunk in iter(lambda: f.read(4096), b""):
					hash_md5.update(chunk)
		except Exception as e:
			self._safe_log("error", f"Error calculating hash for {filepath}: {e}")
			return ""
		return hash_md5.hexdigest()

	##~~ AssetPlugin mixin

	def get_assets(self):
		# Define your plugin's asset files to automatically include in the
		# core UI here.
		return dict(
			js=["js/usbfilewatcher.js"],
			css=["css/usbfilewatcher.css"],
			less=["less/usbfilewatcher.less"]
		)

	##~~ Softwareupdate hook

	def get_update_information(self):
		# Define the configuration for your plugin to use with the Software Update
		# Plugin here. See https://github.com/foosel/OctoPrint/wiki/Plugin:-Software-Update
		# for details.
		return dict(
			usbfilewatcher=dict(
				displayName="USB File Watcher Plugin",
				displayVersion=self._plugin_version,

				# version check: github repository
				type="github_release",
				user="Garr-Garr",
				repo="OctoPrint-usbFileWatcher",
				current=self._plugin_version,

				# update method: pip
				pip="https://github.com/Garr-Garr/OctoPrint-usbFileWatcher/archive/{target_version}.zip"
			)
		)

	def get_api_commands(self):
		return dict(
			scanUsb=[],
			toggleMonitoring=[],
			getUsbDevices=[],
			diagnostics=[]
		)

	def on_api_command(self, command, data):
		self._safe_log("info", f"USBFileWatcher on_api_command triggered. Command: {command}. Data: {data}")

		if command == 'scanUsb':
			return self._copy_files_from_usb()
		elif command == 'toggleMonitoring':
			if self._usb_monitor_thread and self._usb_monitor_thread.is_alive():
				self.stop_usb_monitoring()
				return flask.jsonify(result="USB monitoring stopped", monitoring=False)
			else:
				self.start_usb_monitoring()
				return flask.jsonify(result="USB monitoring started", monitoring=True)
		elif command == 'getUsbDevices':
			devices = self._get_usb_mount_points()
			return flask.jsonify(result="USB devices retrieved", devices=devices)
		elif command == 'diagnostics':
			diagnostics = self._run_diagnostics()
			return flask.jsonify(result="Diagnostics completed", diagnostics=diagnostics)

	def get_template_configs(self):
		return [
			dict(
				type="settings",
				custom_bindings=False
			)
		]

	def is_template_autoescaped(self):
		return True

	def is_api_protected(self):
		return True


# Plugin metadata
__plugin_name__ = "USB File Watcher Plugin"
__plugin_pythoncompat__ = ">=3.9,<4"

def __plugin_load__():
	global __plugin_implementation__
	__plugin_implementation__ = UsbfilewatcherPlugin()

	global __plugin_hooks__
	__plugin_hooks__ = {
		"octoprint.plugin.softwareupdate.check_config": __plugin_implementation__.get_update_information
	}

