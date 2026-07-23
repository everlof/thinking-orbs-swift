// Morph: a dotted outline cycling circle → triangle → square → circle —
// the "shaping" state. Each shape is a continuous closed path
// parameterised by arc length (top-centre start, clockwise). Every
// frame the engine blends the two neighbouring paths, then lays the
// dots EVENLY along the blended outline — spacing stays uniform at
// every instant of the morph, holds and transitions alike.

import CoreGraphics
import Foundation

private typealias ShapePath = (Double) -> (Double, Double)

private func smoothE(_ x: Double) -> Double {
    x * x * (3 - 2 * x)
}

private func polyPath(_ verts: [(Double, Double)]) -> ShapePath {
    let V = verts.count
    var L: [Double] = []
    var total = 0.0
    for i in 0..<V {
        let a = verts[i]
        let b = verts[(i + 1) % V]
        let l = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
        L.append(l)
        total += l
    }
    return { f in
        var target = f * total
        var i = 0
        while target > L[i] && i < V - 1 {
            target -= L[i]
            i += 1
        }
        let a = verts[i]
        let b = verts[(i + 1) % V]
        let ff = L[i] > 0 ? min(1, target / L[i]) : 0
        return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
    }
}

private let circle: ShapePath = { f in
    let a = -Double.pi / 2 + f * 2 * .pi
    return (cos(a) * 0.24, sin(a) * 0.24)
}
private let triangle = polyPath([
    (0.0, -0.26),
    (0.24, 0.16),
    (-0.24, 0.16)
])
// 5-vertex walk so the path STARTS at top-centre like the other shapes
private let square = polyPath([
    (0, -0.2),
    (0.2, -0.2),
    (0.2, 0.2),
    (-0.2, 0.2),
    (-0.2, -0.2)
])
private let cycle: [ShapePath] = [circle, triangle, square]

// low floor keeps sparse outlines possible while never degenerating
private func morphN(_ d: Double) -> Int {
    max(6, Int(jsRound(34 * d)))
}

private let hold = 1.4
private let morphDur = 0.9
private let seg = hold + morphDur

let drawMorph: ModeDraw = { ctx, size, t, dark, o in
    let K = cycle.count
    let tc = t.truncatingRemainder(dividingBy: seg * Double(K))
    let k = Int(tc / seg)
    let local = tc - Double(k) * seg
    let m = local > hold ? smoothE((local - hold) / morphDur) : 0
    let sprd = o["spread"] ?? 1

    // blend the two shape PATHS at m, then measure the blended outline
    let pA = cycle[k]
    let pB = cycle[(k + 1) % K]
    let M = 160
    var pts: [(Double, Double)] = []
    pts.reserveCapacity(M)
    for i in 0..<M {
        let f = Double(i) / Double(M)
        let a = pA(f)
        let b = pB(f)
        pts.append(((a.0 + (b.0 - a.0) * m) * sprd, (a.1 + (b.1 - a.1) * m) * sprd))
    }
    var L: [Double] = []
    L.reserveCapacity(M)
    var total = 0.0
    for i in 0..<M {
        let a = pts[i]
        let b = pts[(i + 1) % M]
        let l = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
        L.append(l)
        total += l
    }

    // dot radius depends ONLY on rDot (the size knob); the count sets the
    // gaps. Formed shapes breathe a little (uniform pulse).
    let n = morphN(o["iconD"] ?? 1)
    let re = (o["rDot"] ?? 0.021) * 1.35 * sprd
    let pulse = 1 + 0.02 * sin(local * 3.1)

    var dots: [Dot] = []
    let c2 = size / 2
    var segIdx = 0
    var acc = 0.0
    for k2 in 0..<n {
        let target = (Double(k2) / Double(n)) * total
        while acc + L[segIdx] < target && segIdx < M - 1 {
            acc += L[segIdx]
            segIdx += 1
        }
        let a = pts[segIdx]
        let b = pts[(segIdx + 1) % M]
        let f = L[segIdx] > 0 ? min(1, (target - acc) / L[segIdx]) : 0
        let x = (a.0 + (b.0 - a.0) * f) * pulse
        let y = (a.1 + (b.1 - a.1) * f) * pulse
        dots.append(Dot(
            x: c2 + x * size,
            y: c2 + y * size,
            z: 0,
            r: max(0.35, re * size),
            white: 0.1
        ))
    }
    paint(ctx, &dots, dark: dark, rMin: o["rMin"] ?? 0.3)
}
