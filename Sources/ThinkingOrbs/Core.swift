// Shared primitives for the dotted 3D thought-orbs. Ported from
// thinking-orbs (github.com/Jakubantalik/thinking-orbs): honestly 3D —
// rotated, depth-shaded, z-sorted. Depth is carried by dot size and ink
// weight alone. Plain circle fills only, drawn into a CGContext so the
// same engine serves both the SwiftUI and AppKit front ends.

import CoreGraphics
import Foundation

/// Shared epoch so simultaneously mounted orbs animate in phase,
/// whichever front end hosts them.
let orbEpoch = Date()

struct Dot {
    var x: Double
    var y: Double
    var z: Double
    var r: Double
    /// Ink value: 0 = darkest ink on paper. Mirrored on dark themes.
    var white: Double
    var a: Double = 1
}

/// A stroked edge between two projected points (the `connecting` web).
struct Line {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    /// Ink value, same convention as `Dot.white`.
    var white: Double
    var a: Double = 1
    var w: Double
}

typealias Projector = (Double, Double, Double) -> (Double, Double, Double)

func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double {
    a + (b - a) * f
}

func frac(_ x: Double) -> Double {
    x - floor(x)
}

/// Value noise on a 2-D lattice — smooth, deterministic, cheap.
func vnoise(_ x: Double, _ y: Double) -> Double {
    let xi = floor(x)
    let yi = floor(y)
    var fx = x - xi
    var fy = y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    let a = hashD(xi, yi)
    let b = hashD(xi + 1, yi)
    let c = hashD(xi, yi + 1)
    let d = hashD(xi + 1, yi + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
}

/// Deterministic hash in [0, 1).
func hashD(_ a: Double, _ b: Double) -> Double {
    let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
    return h - h.rounded(.down)
}

/// Stable directions on a unit sphere (Fibonacci lattice).
func fibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
    let golden = Double.pi * (3 - 5.0.squareRoot())
    let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
    let rad = (1 - y * y).squareRoot()
    let a = Double(i) * golden
    return (rad * cos(a), y, rad * sin(a))
}

/// Shortest signed angular distance, wrapped to (-π, π].
func angleDelta(_ a: Double, _ b: Double) -> Double {
    atan2(sin(a - b), cos(a - b))
}

/// Shared spin + tilt + orthographic projection.
func makeProj(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) -> Projector {
    let st = sin(tilt)
    let ct = cos(tilt)
    let sy = sin(yaw)
    let cyw = cos(yaw)
    return { x, y, z in
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale, cy - y1 * scale, z2)
    }
}

/// Painter: z-sort far→near, matte dots. On dark substrates the ink value
/// is mirrored (1 - white) so near dots read bright — the same depth
/// language on an inverted substrate.
///
/// A `tint` colours the ink instead of leaving it grayscale. Depth then
/// rides on opacity rather than luminance: a dot's visibility against its
/// own ground is `1 - white` whichever substrate it sits on (grayscale
/// resolves to `dark ? 1 - w : w`, and a dot is visible in proportion to
/// its distance from the ground either way), so a tinted orb reads the
/// same in light and dark — only in the accent's hue. That is what lets a
/// caller drive the whole mark from one theme colour.
func paint(_ cg: CGContext, _ dots: inout [Dot], dark: Bool, rMin: Double = 0.3, tint: CGColor? = nil) {
    let ink = tint.map(srgbComponents)
    dots.sort { $0.z < $1.z }
    for d in dots {
        if d.a < 0.02 { continue }
        let w = min(1, max(0, d.white))
        if let ink {
            // `1 - w` is the depth cue the grayscale path spends on luminance;
            // a coloured ink spends it on alpha and keeps the hue constant.
            let visibility = 1 - w
            cg.setFillColor(CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: d.a * visibility * ink.a))
        } else {
            let g = dark ? 1 - w : w
            cg.setFillColor(CGColor(srgbRed: g, green: g, blue: g, alpha: d.a))
        }
        let r = max(rMin, d.r)
        cg.fillEllipse(in: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2))
    }
}

/// Stroke pass for edge-based modes. Runs before `paint` so nodes sit on top.
/// The optional tint follows the same depth-as-opacity rule as dotted ink.
func paintLines(_ cg: CGContext, _ lines: [Line], dark: Bool, tint: CGColor? = nil) {
    let ink = tint.map(srgbComponents)
    for line in lines {
        if line.a < 0.02 { continue }
        let white = min(1, max(0, line.white))
        if let ink {
            let visibility = 1 - white
            cg.setStrokeColor(CGColor(
                srgbRed: ink.r,
                green: ink.g,
                blue: ink.b,
                alpha: line.a * visibility * ink.a
            ))
        } else {
            let grey = dark ? 1 - white : white
            cg.setStrokeColor(CGColor(
                srgbRed: grey,
                green: grey,
                blue: grey,
                alpha: line.a
            ))
        }
        cg.setLineWidth(line.w)
        cg.beginPath()
        cg.move(to: CGPoint(x: line.x1, y: line.y1))
        cg.addLine(to: CGPoint(x: line.x2, y: line.y2))
        cg.strokePath()
    }
}

/// A colour's sRGB components, converting from whatever space it arrived in
/// so an accent handed over in a device or catalog space still reads. Falls
/// back to treating a lone component as grey, then to opaque black.
func srgbComponents(_ color: CGColor) -> (r: Double, g: Double, b: Double, a: Double) {
    if let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
       let c = converted.components, c.count >= 4 {
        return (Double(c[0]), Double(c[1]), Double(c[2]), Double(c[3]))
    }
    if let c = color.components, let first = c.first {
        let g = Double(first)
        return (g, g, g, Double(color.alpha))
    }
    return (0, 0, 0, Double(color.alpha))
}

/// Dot radii were tuned for a 300pt frame; sub-linear scaling keeps small
/// spinners legible. Lower pow = radii shrink less with size.
func radiusScale(_ size: Double, _ power: Double) -> Double {
    pow(size / 300, power)
}

/// Matches JS Math.round for the non-negative values used here.
func jsRound(_ x: Double) -> Double {
    x.rounded(.toNearestOrAwayFromZero)
}
