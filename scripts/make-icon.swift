import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205).fill()
    let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 500, weight: .light))!
        .withSymbolConfiguration(.init(paletteColors: [.white]))!
    let ratio = symbol.size.width / symbol.size.height
    symbol.draw(in: NSRect(x: 210, y: 512 - 302 / ratio, width: 604, height: 604 / ratio))
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 && size != 64 {
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    if size >= 32 && size != 128 {
        let logical = size / 2
        try png.write(to: directory.appendingPathComponent("icon_\(logical)x\(logical)@2x.png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", root.appendingPathComponent("Packaging/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
