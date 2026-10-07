import AVFoundation
import Cocoa
import FlutterMacOS

class AppLifecycleHandler {

    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setDockVisibility":
            guard let args = call.arguments as? [String: Any],
                  let mode = args["mode"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing mode argument", details: nil))
                return
            }
            setDockVisibility(mode: mode, result: result)

        case "activateApp":
            // A menu bar accessory opens new windows behind the frontmost app.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                result(nil)
            }

        case "microphoneStatus":
            // Three states, not a bool: setup offers "Allow" only when macOS can
            // still ask, and sends a denied user to System Settings instead.
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: result("granted")
            case .notDetermined: result("notDetermined")
            default: result("denied")
            }

        case "requestMicrophone":
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { result(granted) }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    static func setDockVisibility(mode: String, result: @escaping FlutterResult) {
        NSLog("AppLifecycleHandler: Setting dock visibility to: \(mode)")

        DispatchQueue.main.async {
            let activationPolicy: NSApplication.ActivationPolicy

            switch mode.lowercased() {
            case "menubaronly":
                // accessory = no Dock icon, has menu bar when active
                activationPolicy = .accessory
                NSLog("AppLifecycleHandler: Setting activation policy to accessory (menu bar only)")

            case "dockonly":
                // regular = appears in Dock, has menu bar, acts like normal app
                // Note: "Dock only" isn't truly possible on macOS - apps in Dock get menu bar too
                // We use .regular and hide menu bar items programmatically if needed
                activationPolicy = .regular
                NSLog("AppLifecycleHandler: Setting activation policy to regular (Dock + menu bar)")

            case "both":
                // regular = appears in Dock, has menu bar when active
                activationPolicy = .regular
                NSLog("AppLifecycleHandler: Setting activation policy to regular (both Dock and menu bar)")

            default:
                NSLog("AppLifecycleHandler: Unknown mode: \(mode), defaulting to accessory")
                result(FlutterError(code: "INVALID_MODE",
                                  message: "Invalid mode: \(mode). Expected 'menuBarOnly', 'dockOnly', or 'both'",
                                  details: nil))
                return
            }

            // Apply the activation policy
            let success = NSApp.setActivationPolicy(activationPolicy)

            if success {
                NSLog("AppLifecycleHandler: Successfully set activation policy to \(activationPolicy.rawValue)")

                // If we're switching to regular (Dock visible), activate the app to make it appear
                if activationPolicy == .regular {
                    NSApp.activate(ignoringOtherApps: true)
                }

                result(nil)
            } else {
                NSLog("AppLifecycleHandler: Failed to set activation policy")
                result(FlutterError(code: "ACTIVATION_POLICY_FAILED",
                                  message: "Failed to set activation policy to \(mode)",
                                  details: nil))
            }
        }
    }
}
