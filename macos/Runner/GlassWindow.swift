import Cocoa
import FlutterMacOS

/// Black glass behind the settings and setup windows (design "F").
///
/// Those windows are desktop_multi_window children, each its own Flutter
/// engine with no plugins, so flutter_acrylic is not available there. Instead
/// a dark `NSVisualEffectView` goes behind the Flutter view and Flutter paints
/// a translucent near-black tint over it (`FocusColors.glass.bg`).
///
/// The blur is inserted into the window's frame view, BELOW the content view,
/// rather than by swapping `contentViewController` for a wrapper: the plugin's
/// window teardown casts `contentViewController` to `FlutterViewController` to
/// shut the engine down, and a wrapper would leak one engine per window opened.
///
/// "Reduce transparency" is handled by AppKit: the effect view turns solid.
enum GlassWindow {
    static func apply(to controller: FlutterViewController) {
        controller.backgroundColor = .clear

        // The plugin calls back from inside its window's initializer; finish
        // that first so the window is fully configured.
        DispatchQueue.main.async {
            guard let window = controller.view.window,
                  let content = window.contentView,
                  let frameView = content.superview else { return }

            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)

            let glass = NSVisualEffectView(frame: frameView.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            frameView.addSubview(glass, positioned: .below, relativeTo: content)
        }
    }
}
