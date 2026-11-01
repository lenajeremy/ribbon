import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The blocked screen, in Ribbon's colors: white, the orb, what the session is for and how long it has left,
/// and one black button to close the app.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make()
    }

    private func make() -> ShieldConfiguration {
        let session = SharedStore.active
        let title = session.map { "Blocked during \($0.profile.name)" } ?? "Blocked by Ribbon"
        var subtitle = "Ribbon is keeping this closed while you focus."
        if let session {
            let now = Date()
            if let window = session.window {
                subtitle = "You're working on \(session.task). The rules stay on until \(Format.time(window.end))."
            } else {
                subtitle = "You're working on \(session.task). \(Format.duration(session.timeLeft(at: now))) left."
            }
        }
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: Theme.ui(light: 0xFFFFFF, dark: 0x212121),
            icon: Self.orb(),
            title: ShieldConfiguration.Label(text: title, color: Theme.ui(light: 0x0D0D0D, dark: 0xECECEC)),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Theme.ui(light: 0x8F8F8F, dark: 0x9B9B9B)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: Theme.ui(light: 0xFFFFFF, dark: 0x212121)),
            primaryButtonBackgroundColor: Theme.ui(light: 0x0D0D0D, dark: 0xECECEC),
            secondaryButtonLabel: nil)
    }

    /// The orb, drawn: an ember sphere lit from the top left.
    static func orb(size: CGFloat = 72) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let cg = context.cgContext
            let colors = [UIColor(hex: 0xFFC46B).cgColor, UIColor(hex: 0xFF5A36).cgColor, UIColor(hex: 0xE8235F).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) else { return }
            let inset = size * 0.08
            let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
            cg.addEllipse(in: rect)
            cg.clip()
            cg.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.3),
                                  startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.7,
                                  options: [.drawsAfterEndLocation])
        }
    }
}
