// Ribbon: an undulating sash of parallel strands rides a great circle —
// the "composing" state. The tuned preset freezes the 3D tumble
// (spin 0), leaving the traveling undulation on a fixed band.

import CoreGraphics
import Foundation

let drawRibbon: ModeDraw = { ctx, size, t, dark, o, tint in
    let cx = size / 2
    let cy = size / 2
    let R = (size / 2) * 0.78
    // spin scales the 3D tumble; spin=0 freezes the band's orientation,
    // leaving only the traveling undulation
    let spin = o["spin"] ?? 1
    let pt = makeProj(yaw: t * 0.1 * spin, tilt: 0.3, cx: cx, cy: cy, scale: 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)

    var dots: [Dot] = []
    let ghostN = Int(o["ghostN"] ?? 150)
    for i in 0..<ghostN {
        let d = fibDir(i, ghostN)
        let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
        let depth = (z / R + 1) / 2
        dots.append(Dot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
    }

    // the band plane, precessing (frozen when spin=0)
    let ya = t * 0.24 * spin
    let ta = 0.55 + 0.3 * sin(t * 0.18) * spin
    let ux = cos(ya)
    let uy = 0.0
    let uz = sin(ya)
    let vx = -uz * sin(ta)
    let vy = cos(ta)
    let vz = ux * sin(ta)
    // plane normal n = u × v
    let nx = uy * vz - uz * vy
    let ny = uz * vx - ux * vz
    let nz = ux * vy - uy * vx

    let baseLanes = o["lanes"] ?? 5
    let segs = Int(o["segs"] ?? 88)
    let lanes = max(1, Int(jsRound(baseLanes * (o["bandMul"] ?? 1))))
    for w in 0..<lanes {
        let laneOff = (Double(w) - Double(lanes - 1) / 2) * 0.075
        let edge = abs(Double(w) - Double(lanes - 1) / 2) / max(1, Double(lanes - 1) / 2)
        for k in 0..<segs {
            let a = (Double(k) / Double(segs)) * 2 * .pi
            // the undulation: two traveling waves along the band; wobMul
            // scales the deformation — 0 is a clean band
            let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22)
                + 0.07 * sin(a * 5 + t * 1.1)) * (o["wobMul"] ?? 1)
            let off = laneOff + wob
            let x = ux * cos(a) + vx * sin(a) + nx * off
            let y = uy * cos(a) + vy * sin(a) + ny * off
            let z = uz * cos(a) + vz * sin(a) + nz * off
            let l = (x * x + y * y + z * z).squareRoot()
            let (px, py, zr) = pt((x / l) * R, (y / l) * R, (z / l) * R)
            let depth = (zr / R + 1) / 2
            dots.append(Dot(
                x: px, y: py, z: zr,
                r: ((o["rBase"] ?? 1.1) + (o["rDepth"] ?? 1.7) * depth) * (1 - 0.25 * edge) * rs,
                white: 0.52 - 0.44 * depth + 0.18 * edge,
                a: 0.4 + 0.6 * depth
            ))
        }
    }
    paint(ctx, &dots, dark: dark, rMin: o["rMin"] ?? 0.3, tint: tint)
}
