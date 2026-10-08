// Draws the app icon's mark into Resources/AppIcon.icon/Assets: an R built from three shapes on a 2 × 4 grid
// (a square stem, a half-disc bowl, a triangle leg), traced as one outline in one ink color. No gradients.
// Run: swift scripts/make_icon.swift
import AppKit

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Resources/AppIcon.icon/Assets").standardized

let u: CGFloat = 152
let x0 = (1024 - 2 * u) / 2 + u * 0.06, bottom = (1024 - 4 * u) / 2   // nudged right: the bowl carries visual weight
let mid = bottom + 2 * u, stemRight = x0 + u

for dark in [false, true] {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(dark ? CGColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1)
                          : CGColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: bottom))
    path.addLine(to: CGPoint(x: x0, y: mid + 2 * u))
    path.addLine(to: CGPoint(x: stemRight, y: mid + 2 * u))
    path.addArc(center: CGPoint(x: stemRight, y: mid + u), radius: u, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    path.addLine(to: CGPoint(x: stemRight + u, y: bottom))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: assets.appendingPathComponent(dark ? "mark-dark.png" : "mark.png"))
}
print("Wrote the icon mark to \(assets.path)")
