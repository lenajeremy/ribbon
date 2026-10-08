import AppKit
import SwiftUI

/// A transparent, borderless panel that floats above everything (full-screen apps included) on every Space,
/// without ever activating the app, so it never steals focus from what you're working on.
class FloatingPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
    }
}

/// Covers a screen's visible area. Clicks pass through everywhere except the orb (see FocusController.pollMouse).
final class OverlayPanel: FloatingPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Holds the task text field. Takes keyboard focus without activating the app.
final class InputPanel: FloatingPanel {
    override var canBecomeKey: Bool { true }
}

/// Lets the first click on a not-yet-focused panel reach SwiftUI.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
