// Draws the app icon and writes AppIcon.icns. Run via tools/make_icon.sh.
// Kept as code rather than a checked-in PNG so the icon stays tweakable.
import AppKit

let side = 1024
let inset: CGFloat = 92                      // macOS icons don't fill their canvas
let art = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2,
                 height: CGFloat(side) - inset * 2)
let radius = art.width * 0.2237              // Big Sur squircle ratio

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// Deterministic jitter, so rebuilding produces a byte-identical icon.
struct LCG {
    var state: UInt64 = 0x2545F4914F6CDD1D
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10000) / 10000
    }
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
let ctx = NSGraphicsContext.current!.cgContext

let squircle = CGPath(roundedRect: art, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow beneath the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
              color: rgb(0, 0, 0, 0.45))
ctx.addPath(squircle)
ctx.setFillColor(rgb(20, 26, 36))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Slate body: subtle vertical gradient, lighter at the top.
let space = CGColorSpaceCreateDeviceRGB()
let body = CGGradient(colorsSpace: space,
                      colors: [rgb(45, 55, 72), rgb(17, 22, 31)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: art.maxY),
                       end: CGPoint(x: 0, y: art.minY), options: [])

// The sweep runs at this angle; residue is culled against the same line so
// nothing survives on the side the wiper has already passed.
let theta: CGFloat = -22 * .pi / 180
/// Signed distance from the wiper edge — negative is swept clean.
func acrossSweep(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    let dx = x - art.midX, dy = y - art.midY
    return dx * cos(theta) + dy * sin(theta)
}

// Residue: the leftover files still to be swept away.
var rng = LCG()
let cell = art.width * 0.098
for row in 0..<11 {
    for col in 0..<11 {
        let x = art.minX + CGFloat(col) * cell + rng.next() * cell * 0.45
        let y = art.minY + art.height * 0.10 + CGFloat(row) * cell + rng.next() * cell * 0.45
        let d = 16 + rng.next() * 20
        guard x < art.maxX - 46, y < art.maxY - 46 else { continue }

        let across = acrossSweep(x, y)
        guard across > 70 else { continue }               // already swept
        let ramp = min(1, (across - 70) / (art.width * 0.34))
        ctx.setFillColor(rgb(158, 178, 208, 0.12 + ramp * 0.34))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: d, height: d),
                           cornerWidth: d * 0.28, cornerHeight: d * 0.28, transform: nil))
        ctx.fillPath()
    }
}

// The sweep: a soft diagonal band with a bright leading edge.
ctx.saveGState()
ctx.translateBy(x: art.midX, y: art.midY)
ctx.rotate(by: theta)

let bandW = art.width * 0.17
let half = art.height * 0.95
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(45, 212, 191, 0.00),
                               rgb(94, 234, 212, 0.22),
                               rgb(190, 250, 240, 0.50)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.saveGState()
ctx.clip(to: CGRect(x: -bandW, y: -half, width: bandW, height: half * 2))
ctx.drawLinearGradient(glow, start: CGPoint(x: -bandW, y: 0),
                       end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Leading edge — the wiper itself.
let edge = CGGradient(colorsSpace: space,
                      colors: [rgb(255, 255, 255, 0.0),
                               rgb(220, 255, 250, 0.95),
                               rgb(255, 255, 255, 0.0)] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.saveGState()
ctx.clip(to: CGRect(x: -9, y: -half, width: 18, height: half * 2))
ctx.drawLinearGradient(edge, start: CGPoint(x: 0, y: -half),
                       end: CGPoint(x: 0, y: half), options: [])
ctx.restoreGState()
ctx.restoreGState()

// Glass highlight across the top.
let sheen = CGGradient(colorsSpace: space,
                       colors: [rgb(255, 255, 255, 0.13), rgb(255, 255, 255, 0.0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: art.maxY),
                       end: CGPoint(x: 0, y: art.midY), options: [])

ctx.restoreGState()

// Hairline rim for definition against dark Dock backgrounds.
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(255, 255, 255, 0.14))
ctx.setLineWidth(2.5)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
