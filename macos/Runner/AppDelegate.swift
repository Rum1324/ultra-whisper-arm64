import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusBarController: StatusBarController?
  private var statusBarEventChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    let controller : FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    let keystrokeChannel = FlutterMethodChannel(name: "com.glassywhisper.keystroke",
                                              binaryMessenger: controller.engine.binaryMessenger)

    keystrokeChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      KeystrokeHandler.handleMethodCall(call: call, result: result)
    })

    let lifecycleChannel = FlutterMethodChannel(name: "com.glassywhisper.app_lifecycle",
                                              binaryMessenger: controller.engine.binaryMessenger)

    lifecycleChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      AppLifecycleHandler.handleMethodCall(call: call, result: result)
    })

    // Volume control channel
    let volumeChannel = FlutterMethodChannel(name: "com.ultrawhisper.volume",
                                            binaryMessenger: controller.engine.binaryMessenger)

    volumeChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      VolumeHandler.handleMethodCall(call: call, result: result)
    })

    // Attempt to restore volume on launch (crash recovery)
    VolumeController.restoreVolumeOnLaunch()

    // Set up status bar controller
    setupStatusBar(controller: controller)

    super.applicationDidFinishLaunching(aNotification)
  }

  private func setupStatusBar(controller: FlutterViewController) {
    // Create status bar controller
    statusBarController = StatusBarController()

    // Create channel for status bar updates from Flutter
    let statusBarChannel = FlutterMethodChannel(
      name: "com.glassywhisper.status_bar",
      binaryMessenger: controller.engine.binaryMessenger
    )

    statusBarChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self, let statusBarController = self.statusBarController else {
        result(FlutterError(code: "NOT_INITIALIZED", message: "Status bar not initialized", details: nil))
        return
      }
      StatusBarController.handleMethodCall(call: call, result: result, controller: statusBarController)
    }

    // Create channel for status bar events to Flutter
    statusBarEventChannel = FlutterMethodChannel(
      name: "com.glassywhisper.status_bar_events",
      binaryMessenger: controller.engine.binaryMessenger
    )

    // Wire up status bar callbacks
    statusBarController?.onStartRecording = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("startRecording", arguments: nil)
    }

    statusBarController?.onStopRecording = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("stopRecording", arguments: nil)
    }

    statusBarController?.onOpenSettings = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("openSettings", arguments: nil)
    }

    statusBarController?.onRestart = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("restart", arguments: nil)
    }

    statusBarController?.onCheckForUpdates = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("checkForUpdates", arguments: nil)
    }

    statusBarController?.onQuit = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("quit", arguments: nil)
    }

    statusBarController?.onToggleVolumeDuck = { [weak self] in
      self?.statusBarEventChannel?.invokeMethod("toggleVolumeDuck", arguments: nil)
    }

    NSLog("AppDelegate: Status bar setup completed")
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
