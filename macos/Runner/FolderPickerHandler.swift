import AppKit
import FlutterMacOS
import Foundation

/// Native folder chooser for the settings window.
///
/// Split out the same way as `VolumeHandler`/`KeystrokeHandler`: this decodes
/// arguments and shapes replies, nothing more. It exists because the settings
/// window is a `desktop_multi_window` child with its own Flutter engine, and
/// plugin-provided pickers are not registered there — so the child asks the
/// main window over its own channel, and the main window calls this.
class FolderPickerHandler {

    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickDirectory":
            let args = call.arguments as? [String: Any]
            let initial = args?["initialPath"] as? String

            // NSOpenPanel must run on the main thread, and the app is
            // LSUIElement, so nothing is guaranteed to be frontmost — activate
            // first or the panel can open behind whatever the user is in.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)

                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.prompt = "Choose"
                panel.message = "Where should meeting transcripts and notes be saved?"
                if let initial, !initial.isEmpty,
                   FileManager.default.fileExists(atPath: initial) {
                    panel.directoryURL = URL(fileURLWithPath: initial)
                }

                // `nil` rather than an empty string for a cancelled panel: the
                // caller has to tell "chose nothing" from "chose the root".
                result(panel.runModal() == .OK ? panel.url?.path : nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
