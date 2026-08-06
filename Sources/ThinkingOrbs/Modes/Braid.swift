// Braid: three strands plait around the sphere — the "weaving" state.
// Each strand runs pole to pole on a helix, and a radial breathing term
// makes them trade places, reading as the over/under of a plait.

import CoreGraphics
import Foundation

let drawBraid: ModeDraw = { context, size, time, dark, options, tint in
    let centerX = size / 2
    let centerY = size / 2
    let radius = (size / 2) * 0.76
    let project = makeProj(yaw: time * 0.4, tilt: 0.3, cx: centerX, cy: centerY, scale: 1)
    let radiusScale = radiusScale(size, options["rsPow"] ?? 0.6)

    var dots: [Dot] = []
    let ghostCount = Int(options["ghostN"] ?? 150)
    for index in 0..<ghostCount {
        let direction = fibDir(index, ghostCount)
        let (x, y, z) = project(
            direction.0 * radius,
            direction.1 * radius,
            direction.2 * radius
        )
        let depth = (z / radius + 1) / 2
        dots.append(Dot(
            x: x,
            y: y,
            z: z,
            r: 0.8 * radiusScale,
            white: 0.78,
            a: 0.1 + 0.22 * depth
        ))
    }

    let strandCount = Int(options["strandN"] ?? 52)
    let turns = options["turns"] ?? 3
    for strand in 0..<3 {
        let phase = (Double(strand) / 3) * 2 * Double.pi
        for index in 0..<strandCount {
            // `u` walks pole to pole; the fractional drift slides the whole
            // strand along while its ends fade at the seam.
            let u = (frac(Double(index) / Double(strandCount) + time * 0.045) * 2 - 1) * 0.96
            let surface = sqrt(max(0, 1 - u * u))
            let endFade = min(1, (1 - abs(u)) / 0.1)
            let angle = u * Double.pi * turns + phase
            let weave = 1 + 0.075 * sin(u * Double.pi * turns * 2 + phase * 2 + time * 0.8)
            let radial = surface * radius * weave
            let (x, y, z) = project(
                cos(angle) * radial,
                u * radius * weave,
                sin(angle) * radial
            )
            let depth = (z / radius + 1) / 2
            dots.append(Dot(
                x: x,
                y: y,
                z: z,
                r: ((options["rBase"] ?? 1.2) + (options["rDepth"] ?? 1.8) * depth) * radiusScale,
                white: 0.55 - 0.45 * depth,
                a: endFade * (0.45 + 0.55 * depth)
            ))
        }
    }
    paint(context, &dots, dark: dark, rMin: options["rMin"] ?? 0.3, tint: tint)
}
