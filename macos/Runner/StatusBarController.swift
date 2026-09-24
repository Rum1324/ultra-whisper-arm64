import Cocoa
import FlutterMacOS

class StatusBarController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var recordingMenuItem: NSMenuItem?
    private var meetingMenuItem: NSMenuItem?
    private var volumeDuckMenuItem: NSMenuItem?
    private var skipDuckWhenBluetoothMenuItem: NSMenuItem?
    private var isRecording = false
    private var isMeetingActive = false
    private var volumeDuckEnabled = true  // Default to true
    private var skipDuckWhenBluetoothEnabled = true  // Default to true

    // Callback for menu actions
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onToggleMeeting: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRestart: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?
    var onToggleVolumeDuck: (() -> Void)?
    var onToggleSkipDuckWhenBluetooth: (() -> Void)?

    init() {
        setupStatusBar()
    }

    private func setupStatusBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else {
            NSLog("StatusBarController: Failed to create status bar item")
            return
        }

        // Set initial icon - using app icon
        if let button = statusItem.button {
            // Load the app icon and resize it for menu bar (16x16 or 18x18 for Retina)
            if let appIcon = NSImage(named: "AppIcon") {
                let iconSize = NSSize(width: 18, height: 18)
                appIcon.size = iconSize
                button.image = appIcon
                button.image?.isTemplate = false // Keep original colors
            } else {
                // Fallback to SF Symbol if app icon not found
                NSLog("StatusBarController: App icon not found, using SF Symbol")
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "UltraWhisper")
                button.image?.isTemplate = true
            }
        }

        // Create menu
        menu = NSMenu()
        // Drive enablement ourselves. The Bluetooth sub-option is greyed out
        // while ducking is off, which AppKit's automatic enabling — it only
        // checks that the target responds to the action — would undo.
        menu?.autoenablesItems = false

        // Recording toggle menu item
        recordingMenuItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordingMenuItem?.target = self
        menu?.addItem(recordingMenuItem!)

        // Meeting toggle. Separate from dictation on purpose: a meeting is a
        // long two-track session that outlives any one utterance, so sharing the
        // dictation item would make "stop" ambiguous.
        meetingMenuItem = NSMenuItem(
            title: "Record Meeting",
            action: #selector(toggleMeeting),
            keyEquivalent: ""
        )
        meetingMenuItem?.target = self
        menu?.addItem(meetingMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Volume ducking toggle menu item
        volumeDuckMenuItem = NSMenuItem(
            title: "Reduce System Volume During Recording",
            action: #selector(toggleVolumeDuck),
            keyEquivalent: ""
        )
        volumeDuckMenuItem?.target = self
        volumeDuckMenuItem?.state = .on  // Default to on (checkmark visible)
        menu?.addItem(volumeDuckMenuItem!)

        // Sub-option of the ducking toggle above, scoped to whatever is playing
        // audio right now: headphones want ducking skipped, a speaker does not,
        // and the two cannot share one answer. The title carries the device
        // name so the item never reads as a global switch. Indented and
        // disabled-when-parent-is-off to read as subordinate.
        skipDuckWhenBluetoothMenuItem = NSMenuItem(
            title: "Skip For Current Output Device",
            action: #selector(toggleSkipDuckWhenBluetooth),
            keyEquivalent: ""
        )
        skipDuckWhenBluetoothMenuItem?.target = self
        skipDuckWhenBluetoothMenuItem?.state = .on  // Default to on
        skipDuckWhenBluetoothMenuItem?.indentationLevel = 1
        menu?.addItem(skipDuckWhenBluetoothMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Settings menu item
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu?.addItem(settingsItem)

        menu?.addItem(NSMenuItem.separator())

        // Check for Updates menu item
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu?.addItem(updateItem)

        menu?.addItem(NSMenuItem.separator())

        // Restart menu item
        let restartItem = NSMenuItem(
            title: "Restart",
            action: #selector(restart),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu?.addItem(restartItem)

        // Quit menu item
        let quitItem = NSMenuItem(
            title: "Quit UltraWhisper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        // Attach menu to status item
        statusItem.menu = menu

        NSLog("StatusBarController: Status bar initialized successfully")
    }

    // MARK: - Public Methods

    /// Reflect whether a meeting is being recorded.
    func setMeetingState(_ active: Bool) {
        isMeetingActive = active

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.meetingMenuItem?.title = active ? "Stop Meeting" : "Record Meeting"
            NSLog("StatusBarController: Meeting state updated to \(active)")
        }
    }

    func setRecordingState(_ recording: Bool) {
        isRecording = recording

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update menu item title
            if recording {
                self.recordingMenuItem?.title = "Stop Recording"
                // Keep the same icon but could add a visual indicator
                // For now, we'll keep it simple with just the menu title change
                // Could add a badge or overlay in the future
            } else {
                self.recordingMenuItem?.title = "Start Recording"
                // Restore normal icon if we changed it
                if let button = self.statusItem?.button {
                    if let appIcon = NSImage(named: "AppIcon") {
                        let iconSize = NSSize(width: 18, height: 18)
                        appIcon.size = iconSize
                        button.image = appIcon
                        button.image?.isTemplate = false // Keep original colors
                    }
                }
            }

            NSLog("StatusBarController: Recording state updated to \(recording)")
        }
    }

    func showStatusBar() {
        guard let statusItem = statusItem else { return }
        statusItem.isVisible = true
        NSLog("StatusBarController: Status bar shown")
    }

    func hideStatusBar() {
        guard let statusItem = statusItem else { return }
        statusItem.isVisible = false
        NSLog("StatusBarController: Status bar hidden")
    }

    func setVolumeDuckState(_ enabled: Bool) {
        volumeDuckEnabled = enabled

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update checkmark state
            self.volumeDuckMenuItem?.state = enabled ? .on : .off
            // The sub-option is meaningless when nothing is ducked.
            self.skipDuckWhenBluetoothMenuItem?.isEnabled = enabled

            NSLog("StatusBarController: Volume duck state updated to \(enabled)")
        }
    }

    func setDeviceSkipDuckState(_ enabled: Bool, deviceName: String) {
        skipDuckWhenBluetoothEnabled = enabled

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.skipDuckWhenBluetoothMenuItem?.state = enabled ? .on : .off
            self.skipDuckWhenBluetoothMenuItem?.title = deviceName.isEmpty
                ? "Skip For Current Output Device"
                : "Skip For \(deviceName)"

            NSLog("StatusBarController: Skip-duck state updated to \(enabled) for \(deviceName)")
        }
    }

    // MARK: - Menu Actions

    @objc private func toggleRecording() {
        NSLog("StatusBarController: Toggle recording clicked")
        if isRecording {
            onStopRecording?()
        } else {
            onStartRecording?()
        }
    }

    @objc private func toggleMeeting() {
        NSLog("StatusBarController: Toggle meeting clicked")
        onToggleMeeting?()
    }

    @objc private func toggleVolumeDuck() {
        NSLog("StatusBarController: Volume duck toggle clicked")
        onToggleVolumeDuck?()
    }

    @objc private func toggleSkipDuckWhenBluetooth() {
        NSLog("StatusBarController: Skip-duck-when-Bluetooth toggle clicked")
        onToggleSkipDuckWhenBluetooth?()
    }

    @objc private func openSettings() {
        NSLog("StatusBarController: Settings clicked")
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        NSLog("StatusBarController: Check for updates clicked")
        onCheckForUpdates?()
    }

    @objc private func restart() {
        NSLog("StatusBarController: Restart clicked")
        onRestart?()
    }

    @objc private func quit() {
        NSLog("StatusBarController: Quit clicked")
        onQuit?()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem!)
        NSLog("StatusBarController: Cleaned up status bar")
    }
}

// MARK: - Flutter Method Call Handler

extension StatusBarController {
    static func handleMethodCall(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        controller: StatusBarController
    ) {
        switch call.method {
        case "setRecordingState":
            guard let args = call.arguments as? [String: Any],
                  let recording = args["recording"] as? Bool else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing recording argument",
                    details: nil
                ))
                return
            }
            controller.setRecordingState(recording)
            result(nil)

        case "setMeetingState":
            guard let args = call.arguments as? [String: Any],
                  let active = args["active"] as? Bool else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing active argument",
                    details: nil
                ))
                return
            }
            controller.setMeetingState(active)
            result(nil)

        case "showStatusBar":
            controller.showStatusBar()
            result(nil)

        case "hideStatusBar":
            controller.hideStatusBar()
            result(nil)

        case "setVolumeDuckState":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing enabled argument",
                    details: nil
                ))
                return
            }
            controller.setVolumeDuckState(enabled)
            result(nil)

        case "setDeviceSkipDuckState":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing enabled argument",
                    details: nil
                ))
                return
            }
            controller.setDeviceSkipDuckState(
                enabled,
                deviceName: args["deviceName"] as? String ?? ""
            )
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
