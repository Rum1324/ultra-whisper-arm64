import Foundation
import FlutterMacOS

class VolumeHandler {

    static func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getVolume":
            getVolume(result: result)

        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                  message: "Missing volume argument",
                                  details: nil))
                return
            }
            setVolume(volume: Float32(volume), result: result)

        case "getOutputDeviceInfo":
            getOutputDeviceInfo(result: result)

        case "isMuted":
            checkMuted(result: result)

        case "setMuted":
            guard let args = call.arguments as? [String: Any],
                  let muted = args["muted"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                  message: "Missing muted argument",
                                  details: nil))
                return
            }
            setMuted(muted: muted, result: result)

        case "duckVolume":
            guard let args = call.arguments as? [String: Any],
                  let percentage = args["percentage"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENTS",
                                  message: "Missing percentage argument",
                                  details: nil))
                return
            }
            let persistent = args["persistent"] as? Bool ?? true
            duckVolume(percentage: Float32(percentage), persistent: persistent, result: result)

        case "restoreVolume":
            restoreVolume(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func getVolume(result: @escaping FlutterResult) {
        do {
            let volume = try VolumeController.getCurrentVolume()
            result(Double(volume))
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func setVolume(volume: Float32, result: @escaping FlutterResult) {
        do {
            try VolumeController.setVolume(volume)
            result(nil)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func getOutputDeviceInfo(result: @escaping FlutterResult) {
        do {
            let info = try VolumeController.getOutputDeviceInfo()
            result([
                "uid": info.uid,
                "name": info.name,
                "transportType": Int(info.transportType),
                "isBluetooth": info.isBluetooth,
            ])
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func checkMuted(result: @escaping FlutterResult) {
        do {
            let muted = try VolumeController.isMuted()
            result(muted)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func setMuted(muted: Bool, result: @escaping FlutterResult) {
        do {
            try VolumeController.setMuted(muted)
            result(nil)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func duckVolume(percentage: Float32, persistent: Bool, result: @escaping FlutterResult) {
        do {
            try VolumeController.duckVolume(to: percentage, persistent: persistent)
            result(nil)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    private static func restoreVolume(result: @escaping FlutterResult) {
        do {
            try VolumeController.restoreVolume()
            result(nil)
        } catch {
            result(FlutterError(code: "VOLUME_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
}
