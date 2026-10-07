import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Kept here because `contentViewController` stops being this controller:
  /// macos_window_utils (via flutter_acrylic's `Window.initialize()`) wraps it
  /// in a MacOSWindowUtilsViewController. When Dart got there before
  /// applicationDidFinishLaunching, casting contentViewController crashed the
  /// app on launch.
  private(set) var flutterViewController: FlutterViewController!

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.flutterViewController = flutterViewController
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
