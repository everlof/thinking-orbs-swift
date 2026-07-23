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

typealias Projector = (Double, Double, Double) -> (Double, Double, Double)

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

/// Painter: z-sort far→near, matte grayscale dots. On dark substrates the
/// ink value is mirrored (1 - white) so near dots read bright — the same
/// depth language on an inverted substrate.
func paint(_ cg: CGContext, _ dots: inout [Dot], dark: Bool, rMin: Double = 0.3) {
    dots.sort { $0.z < $1.z }
    for d in dots {
        if d.a < 0.02 { continue }
        let w = min(1, max(0, d.white))
        let g = dark ? 1 - w : w
        cg.setFillColor(CGColor(srgbRed: g, green: g, blue: g, alpha: d.a))
        let r = max(rMin, d.r)
        cg.fillEllipse(in: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2))
    }
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
