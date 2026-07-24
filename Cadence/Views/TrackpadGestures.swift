import SwiftUI
import AppKit

/// Adds trackpad **pinch-zoom** (magnify) and **two-finger scroll → pan** to the canvas.
///
/// Implemented with a local `NSEvent` monitor rather than gesture recognizers so it never
/// intercepts mouse clicks/drags — the backing NSView returns `nil` from `hitTest`, so SwiftUI
/// below keeps handling node selection, dragging, and click-to-connect. Scroll/magnify events are
/// only acted on while the cursor is over the canvas; otherwise they pass through untouched (so the
/// side rails still scroll normally).
struct TrackpadGestures: NSViewRepresentable {
    @Binding var pan: CGSize
    @Binding var zoom: CGFloat
    var zoomRange: ClosedRange<CGFloat> = 0.35...1.5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var parent: TrackpadGestures
        private weak var view: NSView?
        private var monitor: Any?

        init(_ parent: TrackpadGestures) { self.parent = parent }

        func install(on view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let view = self.view, let window = view.window,
                      event.window == window else { return event }
                // Only when the pointer is over the canvas.
                let frame = view.convert(view.bounds, to: nil)
                guard frame.contains(event.locationInWindow) else { return event }

                switch event.type {
                case .magnify:
                    let z = self.parent.zoom * (1 + event.magnification)
                    self.parent.zoom = min(max(z, self.parent.zoomRange.lowerBound), self.parent.zoomRange.upperBound)
                case .scrollWheel:
                    self.parent.pan.width += event.scrollingDeltaX
                    self.parent.pan.height += event.scrollingDeltaY
                default:
                    break
                }
                return event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Transparent to the mouse: clicks/drags fall through to the SwiftUI canvas beneath.
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
