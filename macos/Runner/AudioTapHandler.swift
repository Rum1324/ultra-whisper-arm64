import FlutterMacOS
import Foundation

/// Method-channel front end for `AudioTapController`.
///
/// Split the same way as `VolumeHandler`/`VolumeController`: this file only
/// decodes arguments and shapes replies, the controller holds all the Core Audio
/// logic. Events travel back to Flutter on a second channel, following the
/// `statusBarEventChannel` pattern in `AppDelegate`.
class AudioTapHandler {

    /// One controller for the process. Taps own real system resources, so a
    /// second instance would mean a second aggregate device fighting the first.
    private static var controller: AnyObject?

    /// Set by `AppDelegate` so the controller can push audio and state upward.
    static var eventChannel: FlutterMethodChannel?

    @available(macOS 14.4, *)
    private static func sharedController() -> AudioTapController {
        if let existing = controller as? AudioTapController { return existing }
        let created = AudioTapController()
        created.onAudio = { data in
            // Binary payload, not a list of numbers: this is 16 kHz PCM arriving
            // continuously for the length of a meeting, and the standard codec's
            // typed-data path is the only one that does not copy it element-wise.
            DispatchQueue.main.async {
                eventChannel?.invokeMethod(
                    "systemAudio", arguments: FlutterStandardTypedData(bytes: data))
            }
        }
        created.onSilenceSuspected = {
            DispatchQueue.main.async {
                eventChannel?.invokeMethod("systemAudioSilent", arguments: nil)
            }
        }
        created.onMicActivityChanged = { active in
            DispatchQueue.main.async {
                eventChannel?.invokeMethod("micActivityChanged", arguments: active)
            }
        }
        controller = created
        return created
    }

    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(macOS 14.4, *) else {
            // Core Audio process taps landed in 14.2 and became usable in 14.4.
            // Reported rather than crashed: meeting capture is a feature the app
            // can be without, and dictation must keep working regardless.
            result(FlutterError(
                code: "UNSUPPORTED_OS",
                message: "Meeting capture needs macOS 14.4 or later.",
                details: nil))
            return
        }

        switch call.method {
        case "listAudioProcesses":
            result(AudioTapController.listProcesses().map(\.asDictionary))

        case "preflightAudioPermission":
            result(sharedController().preflightPermission())

        case "startSystemCapture":
            guard let args = call.arguments as? [String: Any],
                  let pids = args["pids"] as? [Int], !pids.isEmpty else {
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                    message: "Missing pids argument", details: nil))
                return
            }
            let wanted = Set(pids.map { pid_t($0) })
            let targets = AudioTapController.listProcesses().filter { wanted.contains($0.pid) }
            guard !targets.isEmpty else {
                result(FlutterError(
                    code: "NO_SUCH_PROCESS",
                    message: "None of those processes are known to Core Audio. A process only "
                        + "appears once it has played audio at least once.",
                    details: nil))
                return
            }
            do {
                try sharedController().startCapture(processObjectIDs: targets.map(\.objectID))
                result(true)
            } catch {
                result(FlutterError(code: "CAPTURE_FAILED",
                                    message: error.localizedDescription, details: nil))
            }

        case "stopSystemCapture":
            sharedController().stopCapture()
            result(true)

        case "isMicActive":
            result(AudioTapController.micIsActive())

        case "startMicMonitoring":
            sharedController().startMicActivityMonitoring()
            result(true)

        case "stopMicMonitoring":
            sharedController().stopMicActivityMonitoring()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
