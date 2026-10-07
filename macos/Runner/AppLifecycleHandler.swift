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

        case "raiseOverlay":
            // Above every other window, but without activating UltraWhisper:
            // the app being dictated into must keep keyboard focus, or the
            // paste lands nowhere. The window stays at normal level, so the
            // next app the user clicks covers it again on its own.
            DispatchQueue.main.async {
                NSApp.windows.first { $0 is MainFlutterWindow }?.orderFrontRegardless()
                result(nil)
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
