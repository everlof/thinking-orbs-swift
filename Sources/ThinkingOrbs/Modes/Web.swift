// Web: a constellation wires itself — the "connecting" state. Nodes drift
// on the sphere under slow value noise; nearby pairs grow an edge, and
// bright packets run along randomly re-picked node pairs.

import CoreGraphics
import Foundation

let drawWeb: ModeDraw = { context, size, time, dark, options, tint in
    let centerX = size / 2
    let centerY = size / 2
    let radius = (size / 2) * 0.8 * (options["spread"] ?? 1)
    // The projector carries the radius as its scale so node vectors stay
    // unit length and neighbour distances remain in unit-sphere space.
    let project = makeProj(yaw: time * 0.12, tilt: 0.32, cx: centerX, cy: centerY, scale: radius)
    let radiusScale = radiusScale(size, options["rsPow"] ?? 0.6)

    let nodeCount = Int(options["nodeN"] ?? 30)
    let threshold = options["thr"] ?? 0.72
    let nodeRadius = options["nodeR"] ?? 1.4
    let nodeRadiusDepth = options["nodeRDepth"] ?? 1.8

    // Fibonacci lattice plus slow noise wander, normalized back to the sphere.
    var nodes: [(Double, Double, Double)] = []
    nodes.reserveCapacity(nodeCount)
    for index in 0..<nodeCount {
        let direction = fibDir(index, nodeCount)
        let i = Double(index)
        let x = direction.0 + 0.3 * (vnoise(i * 0.31 + 9, time * 0.24) - 0.5) * 2
        let y = direction.1 + 0.3 * (vnoise(i * 0.53 + 27, time * 0.21) - 0.5) * 2
        let z = direction.2 + 0.3 * (vnoise(i * 0.77 + 55, time * 0.27) - 0.5) * 2
        let length = sqrt(x * x + y * y + z * z)
        nodes.append((x / length, y / length, z / length))
    }

    var lines: [Line] = []
    var dots: [Dot] = []

    // Edges between close neighbours, with proximity and depth carrying alpha.
    if nodeCount > 1 {
        for first in 0..<(nodeCount - 1) {
            for second in (first + 1)..<nodeCount {
                let dx = nodes[first].0 - nodes[second].0
                let dy = nodes[first].1 - nodes[second].1
                let dz = nodes[first].2 - nodes[second].2
                let distance = sqrt(dx * dx + dy * dy + dz * dz)
                if distance >= threshold { continue }
                let start = project(nodes[first].0, nodes[first].1, nodes[first].2)
                let end = project(nodes[second].0, nodes[second].1, nodes[second].2)
                let depth = ((start.2 + end.2) / 2 + 1) / 2
                lines.append(Line(
                    x1: start.0,
                    y1: start.1,
                    x2: end.0,
                    y2: end.1,
                    white: 0.42,
                    a: (1 - distance / threshold) * (0.3 + 0.55 * depth),
                    w: max(0.6, (options["lineW"] ?? 0.8) * radiusScale)
                ))
            }
        }
    }

    for index in 0..<nodeCount {
        let projected = project(nodes[index].0, nodes[index].1, nodes[index].2)
        let depth = (projected.2 + 1) / 2
        let pulse = 1 + 0.25 * sin(time * 1.4 + Double(index) * 2.7)
        dots.append(Dot(
            x: projected.0,
            y: projected.1,
            z: projected.2,
            r: (nodeRadius + nodeRadiusDepth * depth) * pulse * radiusScale,
            white: 0.55 - 0.45 * depth
        ))
    }

    // Bright packets travel between freshly paired nodes.
    let signalCount = Int(options["signals"] ?? 5)
    for signal in 0..<signalCount {
        let signalValue = Double(signal)
        let segment = floor(time * 0.55 + signalValue * 7.31)
        let first = Int(floor(hashD(segment, signalValue * 3.1 + 1.7) * Double(nodeCount)))
        let second = Int(floor(hashD(segment, signalValue * 5.7 + 4.2) * Double(nodeCount)))
        if first == second { continue }
        let progress = frac(time * 0.55 + signalValue * 7.31)
        let x = lerp(nodes[first].0, nodes[second].0, progress)
        let y = lerp(nodes[first].1, nodes[second].1, progress)
        let z = lerp(nodes[first].2, nodes[second].2, progress)
        let length = max(1e-6, sqrt(x * x + y * y + z * z))
        let projected = project(x / length, y / length, z / length)
        let depth = (projected.2 + 1) / 2
        dots.append(Dot(
            x: projected.0,
            y: projected.1,
            z: projected.2,
            r: (nodeRadius * 1.5 + nodeRadiusDepth * depth) * radiusScale,
            white: 0.05,
            a: 0.5 + 0.5 * depth
        ))
    }

    paintLines(context, lines, dark: dark, tint: tint)
    paint(context, &dots, dark: dark, rMin: options["rMin"] ?? 0.3, tint: tint)
}
