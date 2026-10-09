import Cocoa
import FlutterMacOS

/// Black glass behind the settings and setup windows (design "F").
///
/// Those windows are desktop_multi_window children: each its own Flutter
/// engine with no plugins, so flutter_acrylic is not available there. This
/// does what macos_window_utils does for the main window (the island): the
/// window's content becomes a blur view with Flutter's view inside it, and
/// Flutter paints a translucent near-black tint over it (`FocusColors.glass`).
///
/// Do NOT put the blur view in the window's frame view instead (beside the
/// content view). Measured 2026-10-09 with a 6-way harness: any
/// NSVisualEffectView added there — even with the window left opaque — made
/// AppKit treat clicks over Flutter's content as window drags, so Settings
/// ignored every click and scroll. Transparency alone was harmless. The frame
/// view is private to AppKit; the content view is the supported place.
///
/// "Reduce transparency" is handled by AppKit: the blur turns solid.
enum GlassWindow {
    static func apply(to controller: FlutterViewController) {
        // The plugin calls back from inside its window's initializer; let it
        // finish configuring the window first.
        DispatchQueue.main.async {
            guard let window = controller.view.window,
                  let content = window.contentView else { return }

            controller.backgroundColor = .clear
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentViewController = GlassViewController(flutter: controller, size: content.bounds.size)

            // desktop_multi_window shuts a window's engine down by casting
            // `contentViewController` to FlutterViewController when the window
            // goes away; with the glass controller in that slot the cast fails,
            // so shut it down here instead — once, when the window closes.
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                controller.engine.shutDownEngine()
            }
        }
    }
}

/// A blur root view with Flutter's view inside it, filling it.
final class GlassViewController: NSViewController {
    private let flutter: FlutterViewController
    private let size: NSSize

    init(flutter: FlutterViewController, size: NSSize) {
        self.flutter = flutter
        self.size = size
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        view = glass
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(flutter)
        flutter.view.frame = view.bounds
        flutter.view.autoresizingMask = [.width, .height]
        view.addSubview(flutter.view)
    }
}
