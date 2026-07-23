// Density profiles + the multiplier machinery that scales them. The base
// rows are the upstream `fine` profiles; each shipped preset (state ×
// size) applies count / radius multipliers on top, resolved once per
// (state, size) pair.

import Foundation

typealias ModeOpts = [String: Double]

// 2-D lattices (rings × dots-per-ring) come in pairs — each side takes
// √scale so the TOTAL dot count scales by `scale`; flat lists scale
// linearly. `iconD` sets the morph outline's sampling density.
private let countPairs: [(String, String)] = [
    ("latRings", "lonDensity"),
    ("rings", "lonDensity"),
    ("lanes", "segs")
]
private let countKeys = ["orbitN", "ghostN"]
private let iconDensityKeys = ["iconD"]

// Every key that sets a dot's rendered radius — scaling all of them keeps
// a dot's near/far falloff intact while shrinking or growing the mark.
private let radiusKeys = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth"]

func scaleCounts(_ opts: ModeOpts, _ scale: Double) -> ModeOpts {
    var out = opts
    var done = Set<String>()
    let rt = scale.squareRoot()
    for (a, b) in countPairs {
        if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
            out[a] = max(2, jsRound(va * rt))
            out[b] = max(2, jsRound(vb * rt))
            done.insert(a)
            done.insert(b)
        }
    }
    for k in countKeys {
        if let v = out[k], !done.contains(k) {
            out[k] = max(1, jsRound(v * scale))
        }
    }
    for k in iconDensityKeys {
        if let v = out[k] {
            out[k] = max(0.02, v * scale)
        }
    }
    return out
}

func scaleRadii(_ opts: ModeOpts, _ scale: Double) -> ModeOpts {
    var out = opts
    for k in radiusKeys {
        if let v = out[k] {
            out[k] = v * scale
        }
    }
    // remember the multiplier itself — spacing-derived radii use it,
    // since they aren't based on any single radius key
    out["rSizeMul"] = (out["rSizeMul"] ?? 1) * scale
    return out
}

/// Base (fine) profiles per mode, before preset multipliers.
let baseProfiles: [String: ModeOpts] = [
    "globe": [
        "latRings": 17,
        "lonDensity": 44,
        "rBase": 0.6,
        "rDepth": 1.7,
        "rBoost": 1.0,
        "inkFar": 0.62,
        "inkSpan": 0.54,
        "rsPow": 0.6,
        "rMin": 0.3
    ],
    "orbits": [
        "orbitN": 12,
        "ghostN": 40,
        "ghostR": 0.9,
        "ghostA": 0.5,
        "particles": 3,
        "partR": 1.2,
        "partRDepth": 1.6,
        "rsPow": 0.6,
        "rMin": 0.3
    ],
    "rubik": [
        "latRings": 15,
        "lonDensity": 40,
        "moveCount": 14,
        "rBase": 0.6,
        "rDepth": 1.7,
        "rActive": 0.3,
        "inkFar": 0.62,
        "inkSpan": 0.54,
        "rsPow": 0.6,
        "rMin": 0.3
    ],
    "wave": [
        "rings": 15,
        "lonDensity": 40,
        "rBase": 0.6,
        "rDepth": 1.7,
        "rsPow": 0.6,
        "rMin": 0.3
    ],
    "ribbon": [
        "lanes": 5,
        "segs": 88,
        "ghostN": 150,
        "rBase": 1.1,
        "rDepth": 1.7,
        "rsPow": 0.6,
        "rMin": 0.3
    ],
    "morph": [
        "rDot": 0.021,
        "iconD": 1,
        "rMin": 0.25
    ]
]
