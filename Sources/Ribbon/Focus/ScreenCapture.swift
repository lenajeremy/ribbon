import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

struct Screenshot: Sendable {
    let label: String
    let dataURL: String
}

enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { CGRequestScreenCaptureAccess() }

    /// One downscaled JPEG per display, the display under the cursor first.
    /// The orb's own windows are left out so the model never sees them.
    static func captureAll(activeDisplay: CGDirectDisplayID?, maxSide: Int = 1280) async throws -> [Screenshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ours = content.windows.filter { $0.owningApplication?.processID == pid }
        let displays = content.displays.sorted {
            ($0.displayID == activeDisplay ? 0 : 1, $0.displayID) < ($1.displayID == activeDisplay ? 0 : 1, $1.displayID)
        }

        var shots: [Screenshot] = []
        for (index, display) in displays.enumerated() {
            let config = SCStreamConfiguration()
            let scale = min(1, Double(maxSide) / Double(max(display.width, display.height)))
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
            config.showsCursor = true
            let filter = SCContentFilter(display: display, excludingWindows: ours)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let jpeg = jpegData(image) else { continue }
            let note = display.displayID == activeDisplay ? " (the mouse cursor is on this one)" : ""
            shots.append(Screenshot(
                label: "Display \(index + 1)\(note):",
                dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString()
            ))
        }
        return shots
    }

    @MainActor static func cursorDisplayID() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.displayID
    }

    /// The frontmost app and the title of its front window (titles need Screen Recording permission).
    @MainActor static func frontmost() -> (app: String?, window: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Front to back; skip the untitled helper windows some apps (Chrome) keep in front.
        let title = windows.lazy
            .filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
        return (app.localizedName, title)
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
