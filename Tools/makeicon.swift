import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    )
}

let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 186, yRadius: 186
)
color(0x201E1B).setFill()
squircle.fill()

let center = NSPoint(x: size / 2, y: size / 2)
let ringRadius: CGFloat = 250
let ringWidth: CGFloat = 92

let track = NSBezierPath()
track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
track.lineWidth = ringWidth
track.lineCapStyle = .round
color(0x33302C).setStroke()
track.stroke()

let arc = NSBezierPath()
arc.appendArc(withCenter: center, radius: ringRadius, startAngle: 90, endAngle: -155, clockwise: true)
arc.lineWidth = ringWidth
arc.lineCapStyle = .round
color(0xD97757).setStroke()
arc.stroke()

let dotAngle = -155.0 * .pi / 180.0
let dotCenter = NSPoint(
    x: center.x + ringRadius * cos(dotAngle),
    y: center.y + ringRadius * sin(dotAngle)
)
let dot = NSBezierPath(ovalIn: NSRect(
    x: dotCenter.x - 26, y: dotCenter.y - 26, width: 52, height: 52
))
color(0xF5EFE6).setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
