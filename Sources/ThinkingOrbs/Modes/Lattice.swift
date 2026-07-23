// The sphere-lattice modes: globe (searching), rubik (solving) and
// wave (listening). All draw a lat/long dot field with mode-specific
// motion, then hand off to the shared z-sorted painter.

import CoreGraphics
import Foundation

// --- the shared solver heartbeat (rubik) ------------------------------
// Rapid eased moves scramble, then replay in reverse (palindrome) so
// everything clicks back to solved, rests, repeats.

private struct Move {
    var axis: Int
    var lo: Double
    var hi: Double
    var ang: Double
}

private struct SolveCycle {
    var amount: [Double]
    var active: Int
}

private func solveCycle(_ time: Double, _ count: Int, _ slotDur: Double, _ rest: Double) -> SolveCycle {
    let cyc = 2 * Double(count) * slotDur + rest
    let tc = time.truncatingRemainder(dividingBy: cyc)
    var amount = [Double](repeating: 0, count: count)
    var active = -1
    if tc < 2 * Double(count) * slotDur {
        let slot = Int(tc / slotDur)
        let p = (tc - Double(slot) * slotDur) / slotDur
        let cl = min(1, p / 0.7)
        let ep = 1 - pow(1 - cl, 3) // machine ease-out
        if slot < count {
            for i in 0..<slot { amount[i] = 1 }
            amount[slot] = ep
            active = slot
        } else {
            let u = 2 * count - 1 - slot
            for i in 0..<u { amount[i] = 1 }
            amount[u] = 1 - ep
            active = u
        }
    }
    return SolveCycle(amount: amount, active: active)
}

private func applyMoves(
    _ p: (Double, Double, Double), _ moves: [Move], _ sc: SolveCycle
) -> (Double, Double, Double, Bool) {
    var (x, y, z) = p
    var inActive = false
    for i in 0..<moves.count {
        if sc.amount[i] <= 0 { continue }
        let mv = moves[i]
        let coord = mv.axis == 0 ? x : mv.axis == 1 ? y : z
        if coord < mv.lo || coord >= mv.hi { continue }
        if i == sc.active { inActive = true }
        let a = mv.ang * sc.amount[i]
        let ca = cos(a)
        let sa = sin(a)
        if mv.axis == 0 {
            let y2 = y * ca - z * sa
            z = y * sa + z * ca
            y = y2
        } else if mv.axis == 1 {
            let x2 = x * ca + z * sa
            z = -x * sa + z * ca
            x = x2
        } else {
            let x2 = x * ca - y * sa
            y = x * sa + y * ca
            x = x2
        }
    }
    return (x, y, z, inActive)
}

private func makeMoves(_ count: Int) -> [Move] {
    (0..<count).map { i in
        let axis = min(2, Int(hashD(Double(i), 2.3) * 3))
        let lo = -1.0 + 0.5 * Double(min(3, Int(hashD(Double(i), 5.9) * 4)))
        let dir: Double = hashD(Double(i), 7.7) < 0.5 ? 1 : -1
        return Move(axis: axis, lo: lo, hi: lo + 0.5, ang: dir * .pi / 2)
    }
}

// --- Globe: lat/long field, a scan meridian sweeps — searching --------

let drawGlobe: ModeDraw = { ctx, size, t, dark, o in
    let spin = 0.5
    let cx = size / 2
    let cy = size / 2
    let radius = (size / 2) * 0.82
    let tilt = 0.4 + 0.06 * sin(t * 0.35)
    let pt = makeProj(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius)
    // scan sweeps relative to the spin; scanMul scales that relative rate
    let scan = t * (spin + (1.7 - spin) * (o["scanMul"] ?? 1))
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    let dimBase = o["dimBase"] ?? 1

    var dots: [Dot] = []
    let latRings = Int(o["latRings"] ?? 17)
    let lonDensity = o["lonDensity"] ?? 44
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
            let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
            let depth = (z + 1) / 2
            // the scan: a moving meridian read as a size ripple, not a shine
            let d = angleDelta(lon + t * spin, scan)
            let boost = exp(-(d * d) / 0.18) * max(0, z)
            dots.append(Dot(
                x: px, y: py, z: z,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * boost) * rs,
                white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                // dimBase < 1 fades un-scanned dots so the meridian reads clearly
                a: dimBase + (1 - dimBase) * min(1, boost)
            ))
        }
    }
    paint(ctx, &dots, dark: dark, rMin: o["rMin"] ?? 0.3)
}

// --- Rubik: bands twist in quarter turns, scramble → solve — solving --

let drawRubik: ModeDraw = { ctx, size, t, dark, o in
    let cx = size / 2
    let cy = size / 2
    let R = (size / 2) * 0.82
    let pt = makeProj(yaw: t * 0.55, tilt: 0.35 + 0.1 * sin(t * 0.9), cx: cx, cy: cy, scale: R)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)
    let moveCount = Int(o["moveCount"] ?? 14)
    let moves = makeMoves(moveCount)
    let sc = solveCycle(t, moveCount, 0.42, 1.2)

    var dots: [Dot] = []
    let latRings = Int(o["latRings"] ?? 15)
    let lonDensity = o["lonDensity"] ?? 40
    for li in 0...latRings {
        let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
            let (x, y, z, inActive) = applyMoves((cosLat * cos(lon), sinLat, cosLat * sin(lon)), moves, sc)
            let (px, py, zr) = pt(x, y, z)
            let depth = (zr + 1) / 2
            // the band being turned inks a touch darker — the "hand"
            dots.append(Dot(
                x: px, y: py, z: zr,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (inActive ? (o["rActive"] ?? 0.3) : 0)) * rs,
                white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth - (inActive ? 0.14 : 0)
            ))
        }
    }
    paint(ctx, &dots, dark: dark, rMin: o["rMin"] ?? 0.3)
}

// --- Wave: a waveform rolls through the rings — listening -------------

let drawWave: ModeDraw = { ctx, size, t, dark, o in
    let cx = size / 2
    let cy = size / 2
    // 0.76 base × 1.15 — the undulation pulls the sphere inward, so wave read
    // ~15% smaller than the other lattice modes; scaled up to match them
    let R = (size / 2) * 0.874
    let pt = makeProj(yaw: t * 0.18, tilt: 0.38, cx: cx, cy: cy, scale: 1)
    let rs = radiusScale(size, o["rsPow"] ?? 0.6)

    var dots: [Dot] = []
    let rings = Int(o["rings"] ?? 15)
    let lonDensity = o["lonDensity"] ?? 40
    for ri in 0...rings {
        let lat = -Double.pi / 2 + (Double(ri) / Double(rings)) * .pi
        let cosLat = cos(lat)
        let sinLat = sin(lat)
        // two waves, different tempi — organic, never quite repeating
        let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
        let rr = R * (0.88 + 0.105 * w)
        let lonCount = max(1, Int(jsRound(abs(cosLat) * lonDensity)))
        for lj in 0..<lonCount {
            let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
            let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
            let depth = (z / R + 1) / 2
            let crest = max(0, w)
            dots.append(Dot(
                x: px, y: py, z: z,
                r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                white: 0.66 - 0.56 * depth - 0.1 * crest
            ))
        }
    }
    paint(ctx, &dots, dark: dark, rMin: o["rMin"] ?? 0.3)
}
