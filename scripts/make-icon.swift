// Renders the app icon (1024 px) and all AppIcon.appiconset sizes.
// Usage: swift scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import SwiftUI

struct IconView: View {
    let orange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        Canvas { ctx, size in
            // macOS icon grid: 824 pt squircle centred in 1024.
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            let squircle = Path(roundedRect: tile, cornerRadius: 185, style: .continuous)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 14, y: 10))
            shadowed.fill(squircle, with: .linearGradient(
                Gradient(colors: [Color(white: 0.20), Color(white: 0.07)]),
                startPoint: CGPoint(x: 512, y: tile.minY), endPoint: CGPoint(x: 512, y: tile.maxY)))

            // The notch: black tab hanging from the top edge, rounded bottom corners.
            var inner = ctx
            inner.clip(to: squircle)
            let notch = CGRect(x: 512 - 190, y: tile.minY - 40, width: 380, height: 150)
            inner.fill(Path(roundedRect: notch, cornerRadius: 56, style: .continuous), with: .color(.black))
            // Status "ears" inside the notch.
            inner.fill(Path(ellipseIn: CGRect(x: 512 - 150, y: tile.minY + 42, width: 30, height: 30)), with: .color(orange))
            inner.fill(Path(roundedRect: CGRect(x: 512 + 60, y: tile.minY + 49, width: 90, height: 16), cornerRadius: 8),
                       with: .color(.white.opacity(0.55)))

            // Soft glow under the mascot.
            inner.fill(Path(ellipseIn: CGRect(x: 512 - 300, y: 330, width: 600, height: 520)),
                       with: .radialGradient(Gradient(colors: [orange.opacity(0.35), .clear]),
                                             center: CGPoint(x: 512, y: 590), startRadius: 0, endRadius: 300))
            drawMascot(&inner, center: CGPoint(x: 512, y: 600), s: 520)
        }
        .frame(width: 1024, height: 1024)
    }

    // Same proportions as MascotRenderer (happy eyes, slight tilt of the antenna).
    func drawMascot(_ ctx: inout GraphicsContext, center: CGPoint, s: CGFloat) {
        let width = s * 0.82, height = s * 0.72
        let top = CGPoint(x: center.x, y: center.y - height / 2)
        let tip = CGPoint(x: top.x + s * 0.06, y: top.y - s * 0.16)
        var antenna = Path()
        antenna.move(to: top)
        antenna.addQuadCurve(to: tip, control: CGPoint(x: top.x, y: top.y - s * 0.11))
        ctx.stroke(antenna, with: .color(orange), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        let r = s * 0.065
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r)), with: .color(orange))

        let body = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        ctx.fill(Path(roundedRect: body, cornerRadius: height * 0.42, style: .continuous),
                 with: .linearGradient(Gradient(colors: [orange.mix(with: .white, by: 0.25), orange]),
                                       startPoint: CGPoint(x: body.midX, y: body.minY),
                                       endPoint: CGPoint(x: body.midX, y: body.maxY)))

        let eye = Color.black.opacity(0.85)
        let eyeW = s * 0.11, eyeH = s * 0.17
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: center.x + side * width * 0.22, y: center.y - height * 0.04)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - eyeW / 2, y: c.y - eyeH / 2, width: eyeW, height: eyeH)), with: .color(eye))
        }
    }
}

@MainActor func render(to dir: URL) throws {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let master = dir.appendingPathComponent("icon_1024.png")
    try rep.representation(using: .png, properties: [:])!.write(to: master)

    var images: [[String: String]] = []
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let name = "icon_\(base)x\(base)@\(scale)x.png"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", dir.appendingPathComponent(name).path]
            p.standardOutput = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
            images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
        }
    }
    try FileManager.default.removeItem(at: master)
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: dir.appendingPathComponent("Contents.json"))
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
              : "Resources/Assets.xcassets/AppIcon.appiconset")
try MainActor.assumeIsolated { try render(to: out) }
