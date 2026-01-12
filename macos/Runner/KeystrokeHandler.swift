import Cocoa
import FlutterMacOS
import ApplicationServices

class KeystrokeHandler {
    
    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "sendKeystroke":
            guard let args = call.arguments as? [String: Any],
                  let keystroke = args["keystroke"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing keystroke argument", details: nil))
                return
            }
            sendKeystroke(keystroke: keystroke, result: result)
            
        case "sendKeySequence":
            guard let args = call.arguments as? [String: Any],
                  let keystrokes = args["keystrokes"] as? [String],
                  let delayMs = args["delayMs"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing keystrokes or delayMs arguments", details: nil))
                return
            }
            sendKeySequence(keystrokes: keystrokes, delayMs: delayMs, result: result)
            
        case "hasAccessibilityPermission":
            let hasPermission = AXIsProcessTrusted()
            result(hasPermission)
            
        case "requestAccessibilityPermission":
            requestAccessibilityPermission(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    static func sendKeystroke(keystroke: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try performKeystroke(keystroke: keystroke)
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "KEYSTROKE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    static func sendKeySequence(keystrokes: [String], delayMs: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for (index, keystroke) in keystrokes.enumerated() {
                    try performKeystroke(keystroke: keystroke)
                    
                    // Add delay between keystrokes (except after the last one)
                    if index < keystrokes.count - 1 {
                        usleep(useconds_t(delayMs * 1000)) // Convert milliseconds to microseconds
                    }
                }
                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "KEY_SEQUENCE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    static func performKeystroke(keystroke: String) throws {
        // Check if we have accessibility permissions with detailed logging
        let hasPermission = AXIsProcessTrusted()
        NSLog("🔑 KeystrokeHandler: Accessibility permission status: \(hasPermission)")
        NSLog("🔑 KeystrokeHandler: Attempting keystroke: '\(keystroke)'")

        guard hasPermission else {
            NSLog("❌ KeystrokeHandler: Accessibility permission denied for keystroke: \(keystroke)")
            let errorMsg = "Accessibility permission required. Please grant access in System Settings > Privacy & Security > Accessibility and add UltraWhisper"
            NSLog("❌ Error detail: \(errorMsg)")
            throw NSError(domain: "KeystrokeHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        let components = keystroke.lowercased().split(separator: "+")
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode = 0
        
        // Parse modifiers and key
        for component in components {
            let key = String(component).trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "fn", "function":
                flags.insert(.maskSecondaryFn)
            default:
                // This is the actual key
                keyCode = try getKeyCode(for: key)
            }
        }
        
        NSLog("🔑 KeystrokeHandler: Prepared keystroke with keyCode: \(keyCode), flags: \(flags.rawValue)")

        // Create event source for more reliable event posting in production
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            NSLog("❌ KeystrokeHandler: Failed to create event source")
            throw NSError(domain: "KeystrokeHandler", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create event source - system may be blocking input events"])
        }
        NSLog("✅ KeystrokeHandler: Created event source")

        // Create and post the key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true) else {
            NSLog("❌ KeystrokeHandler: Failed to create key down event for keyCode: \(keyCode)")
            throw NSError(domain: "KeystrokeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create key down event for key: \(keystroke)"])
        }

        keyDownEvent.flags = flags

        // Post the key down event (single posting to avoid duplicates)
        keyDownEvent.post(tap: .cghidEventTap)

        NSLog("✅ KeystrokeHandler: Posted key down event")
        
        // Small delay between key down and key up
        usleep(15000) // 15ms for better reliability
        
        // Create and post the key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            NSLog("❌ KeystrokeHandler: Failed to create key up event for keyCode: \(keyCode)")
            throw NSError(domain: "KeystrokeHandler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create key up event for key: \(keystroke)"])
        }

        keyUpEvent.flags = flags

        // Post the key up event (single posting to avoid duplicates)
        keyUpEvent.post(tap: .cghidEventTap)

        NSLog("✅ KeystrokeHandler: Successfully sent keystroke: \(keystroke)")
    }
    
    static func getKeyCode(for key: String) throws -> CGKeyCode {
        switch key.lowercased() {
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        case "]": return 30
        case "o": return 31
        case "u": return 32
        case "[": return 33
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "'": return 39
        case "k": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "n": return 45
        case "m": return 46
        case ".": return 47
        case "`": return 50
        case "space": return 49
        case "enter", "return": return 36
        case "tab": return 48
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111
        default:
            throw NSError(domain: "KeystrokeHandler", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown key: \(key)"])
        }
    }
    
    static func requestAccessibilityPermission(result: @escaping FlutterResult) {
        NSLog("KeystrokeHandler: Requesting accessibility permission")
        
        // Check if we already have permission
        let currentPermission = AXIsProcessTrusted()
        NSLog("KeystrokeHandler: Current accessibility permission status: \(currentPermission)")
        
        if currentPermission {
            NSLog("KeystrokeHandler: Accessibility permission already granted")
            result(nil)
            return
        }
        
        // Request permission by prompting the user with detailed options
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        
        NSLog("KeystrokeHandler: Prompting user for accessibility permission")
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessEnabled {
            NSLog("KeystrokeHandler: Accessibility permission granted")
            result(nil)
        } else {
            NSLog("KeystrokeHandler: Accessibility permission denied or pending")
            // Enhanced error message for production builds
            let detailedMessage = """
            GlassyWhisper requires Accessibility access to automatically paste transcribed text.
            
            To enable:
            1. Open System Preferences > Privacy & Security > Accessibility
            2. Click the lock to make changes
            3. Add GlassyWhisper to the list and enable it
            4. Restart the app after granting permission
            """
            
            result(FlutterError(code: "PERMISSION_DENIED", 
                              message: detailedMessage,
                              details: ["current_permission": currentPermission]))
        }
    }
}