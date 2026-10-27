import AppKit

/// A menu item that runs a closure, for menus built on the spot.
final class MenuAction: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError("Not used from nibs") }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}
