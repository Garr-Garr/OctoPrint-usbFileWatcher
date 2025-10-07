/*
 * View model for OctoPrint-usbFileWatcher
 *
 * Author: Garrett Broters and Joshua Wills
 * License: AGPLv3
 */
$(function() {
	function UsbfilewatcherViewModel(parameters) {
		var self = this;

		// Observable properties for the UI
		self.lastResult = ko.observable("No operations performed yet");
		self.detectedDevices = ko.observable("Click 'Show Detected USB Devices' to see current devices");
		self.monitoringStatus = ko.observable("Toggle Monitoring");
		self.isMonitoring = ko.observable(false);

		// Inject settings view model
		self.settingsViewModel = parameters[0];

		// Initialize monitoring status on startup
		self.onStartupComplete = function() {
			var usbFileWatcherSettings = self.settingsViewModel.settings.plugins.usbfilewatcher;
			if (usbFileWatcherSettings && usbFileWatcherSettings.autoMonitor()) {
				self.monitoringStatus("Stop Monitoring");
				self.isMonitoring(true);
			} else {
				self.monitoringStatus("Start Monitoring");
				self.isMonitoring(false);
			}
		};

		// Scan USB devices manually
		self.scanUsb = function() {
			self.lastResult("Scanning USB devices...");
			var url = OctoPrint.getSimpleApiUrl("usbfilewatcher");

			OctoPrint.issueCommand(url, "scanUsb", {})
				.done(function(response) {
					if (response && response.result) {
						self.lastResult(response.result);
					}
				})
				.fail(function() {
					self.lastResult("Error: Failed to scan USB devices");
				});
		};

		// Toggle USB monitoring
		self.toggleMonitoring = function() {
			var url = OctoPrint.getSimpleApiUrl("usbfilewatcher");

			OctoPrint.issueCommand(url, "toggleMonitoring", {})
				.done(function(response) {
					if (response && response.result) {
						self.lastResult(response.result);
						if (response.monitoring !== undefined) {
							self.isMonitoring(response.monitoring);
							if (response.monitoring) {
								self.monitoringStatus("Stop Monitoring");
							} else {
								self.monitoringStatus("Start Monitoring");
							}
						}
					}
				})
				.fail(function() {
					self.lastResult("Error: Failed to toggle monitoring");
				});
		};

		// Get detected USB devices
		self.getUsbDevices = function() {
			self.detectedDevices("Detecting USB devices...");
			var url = OctoPrint.getSimpleApiUrl("usbfilewatcher");

			OctoPrint.issueCommand(url, "getUsbDevices", {})
				.done(function(response) {
					if (response && response.devices) {
						if (response.devices.length > 0) {
							self.detectedDevices("Detected USB devices:\n" + response.devices.join("\n"));
						} else {
							self.detectedDevices("No USB devices currently detected");
						}
						self.lastResult(response.result || "USB device scan completed");
					}
				})
				.fail(function() {
					self.detectedDevices("Error: Failed to detect USB devices");
				});
		};

		// Handle plugin messages
		self.onDataUpdaterPluginMessage = function(plugin, data) {
			if (plugin != "usbfilewatcher") {
				return;
			}

			// Handle any plugin messages if needed in the future
			if (data.status !== undefined) {
				self.lastResult(data.status);
			}
		};

		// Convert array settings to newline-separated strings for display
		self.onBeforeBinding = function() {
			if (self.settingsViewModel && self.settingsViewModel.settings.plugins.usbfilewatcher) {
				var settings = self.settingsViewModel.settings.plugins.usbfilewatcher;

				// Convert watchFolders array to string for textarea
				if (ko.isObservable(settings.watchFolders) && Array.isArray(settings.watchFolders())) {
					settings.watchFolders(settings.watchFolders().join("\n"));
				}

				// Convert copyFileTypes array to string for input
				if (ko.isObservable(settings.copyFileTypes) && Array.isArray(settings.copyFileTypes())) {
					settings.copyFileTypes(settings.copyFileTypes().join(","));
				}

				// Ensure debug_logging is properly initialized as boolean
				if (ko.isObservable(settings.debug_logging) && typeof settings.debug_logging() !== 'boolean') {
					settings.debug_logging(settings.debug_logging() === true || settings.debug_logging() === "true");
				}
			}
		};

		// Convert strings back to arrays before saving
		self.onSettingsBeforeSave = function() {
			if (self.settingsViewModel && self.settingsViewModel.settings.plugins.usbfilewatcher) {
				var settings = self.settingsViewModel.settings.plugins.usbfilewatcher;

				// Convert watchFolders string to array
				if (ko.isObservable(settings.watchFolders) && typeof settings.watchFolders() === 'string') {
					var folders = settings.watchFolders().split('\n').map(function(f) {
						return f.trim();
					}).filter(function(f) {
						return f.length > 0;
					});
					settings.watchFolders(folders);
				}

				// Convert copyFileTypes string to array
				if (ko.isObservable(settings.copyFileTypes) && typeof settings.copyFileTypes() === 'string') {
					var types = settings.copyFileTypes().split(',').map(function(t) {
						return t.trim();
					}).filter(function(t) {
						return t.length > 0;
					});
					settings.copyFileTypes(types);
				}

				// Ensure debug_logging is saved as boolean
				if (ko.isObservable(settings.debug_logging)) {
					settings.debug_logging(settings.debug_logging() === true);
				}
			}
		};
	}

	/* view model class, parameters for constructor, container to bind to
	 * Please see http://docs.octoprint.org/en/master/plugins/viewmodels.html#registering-custom-viewmodels for more details
	 * and a full list of the available options.
	 */
	OCTOPRINT_VIEWMODELS.push({
		construct: UsbfilewatcherViewModel,
		// ViewModels your plugin depends on, e.g. loginStateViewModel, settingsViewModel, ...
		dependencies: ["settingsViewModel"],
		// Elements to bind to, e.g. #settings_plugin_usbfilewatcher, #tab_plugin_usbfilewatcher, ...
		elements: ["#usbfilewatcher_settings"]
	});
});
