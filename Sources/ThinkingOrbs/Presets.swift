// The shipped tunings: six states × two sizes, ported verbatim from the
// upstream tuning session. `count`/`size` are multipliers over the base
// fine profiles; `speed` multiplies the shared clock.

import CoreGraphics
import Foundation

/// The six shipped states — each a hand-tuned animation:
/// - `working`   — particles on tilted orbits
/// - `searching` — a scan meridian sweeps a dotted globe
/// - `solving`   — bands scramble in quarter turns, then click back
/// - `listening` — a waveform rolls through latitude rings
/// - `composing` — an undulating multi-band sash
/// - `shaping`   — a dotted outline morphs circle → triangle → square
public enum OrbState: String, CaseIterable, Sendable {
    case working, searching, solving, listening, composing, shaping

    /// Human-readable label, used as the orb's accessibility label.
    public var label: String {
        switch self {
        case .working: return "Working…"
        case .searching: return "Searching…"
        case .solving: return "Solving…"
        case .listening: return "Listening…"
        case .composing: return "Composing…"
        case .shaping: return "Shaping…"
        }
    }
}

/// Rendered size in points. Exactly two tuned presets ship: 64
/// (chat-avatar scale) and 20 (inline-text scale). Each size carries its
/// own dot count, dot size and speed tuning — they are separate designs,
/// not a scale factor.
public enum OrbSize: Int, CaseIterable, Sendable {
    case px64 = 64
    case px20 = 20
}

/// Theme mode. `auto` follows the SwiftUI environment color scheme;
/// `dark` / `light` pin the palette regardless of context. Dark renders
/// light ink on the transparent canvas (for dark backgrounds); light
/// renders dark ink (for light backgrounds).
public enum OrbTheme: Sendable {
    case auto, dark, light
}

enum ModeKey: String {
    case orbits, globe, rubik, wave, ribbon, morph

    var draw: ModeDraw {
        switch self {
        case .orbits: return drawOrbits
        case .globe: return drawGlobe
        case .rubik: return drawRubik
        case .wave: return drawWave
        case .ribbon: return drawRibbon
        case .morph: return drawMorph
        }
    }
}

typealias ModeDraw = (_ cg: CGContext, _ size: Double, _ t: Double, _ dark: Bool, _ o: ModeOpts, _ tint: CGColor?) -> Void

let stateToMode: [OrbState: ModeKey] = [
    .working: .orbits,
    .searching: .globe,
    .solving: .rubik,
    .listening: .wave,
    .composing: .ribbon,
    .shaping: .morph
]

private struct Preset {
    var speed: Double
    var count: Double
    var size: Double
    /// Extra mode opts merged verbatim after scaling.
    var extra: ModeOpts = [:]
}

private let presets: [ModeKey: [OrbSize: Preset]] = [
    .orbits: [
        .px64: Preset(speed: 1.885, count: 1, size: 1),
        .px20: Preset(speed: 3.9, count: 0.238, size: 2.4)
    ],
    .globe: [
        .px64: Preset(speed: 2.015, count: 0.42, size: 1.15, extra: ["scanMul": 4.08, "dimBase": 0.45]),
        .px20: Preset(speed: 2.665, count: 0.105, size: 1.75, extra: ["scanMul": 4.335, "dimBase": 0.45])
    ],
    .rubik: [
        .px64: Preset(speed: 1.82, count: 0.35, size: 1.05),
        .px20: Preset(speed: 1.95, count: 0.088, size: 1.9)
    ],
    .wave: [
        .px64: Preset(speed: 4.388, count: 0.341, size: 1),
        .px20: Preset(speed: 3.998, count: 0.105, size: 1.6)
    ],
    .ribbon: [
        .px64: Preset(speed: 2.34, count: 0.25, size: 0.85, extra: ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
        .px20: Preset(speed: 3.12, count: 0.051, size: 1.073, extra: ["spin": 0, "bandMul": 4.94, "wobMul": 1])
    ],
    .morph: [
        .px64: Preset(speed: 2.405, count: 0.54, size: 0.395, extra: ["spread": 1.45]),
        .px20: Preset(speed: 2.08, count: 0.53, size: 1.011, extra: ["spread": 1.45])
    ]
]

struct Resolved {
    var mode: ModeKey
    var speed: Double
    var opts: ModeOpts
}

/// Resolve a (state, size) pair to its mode + fully-scaled draw options.
func resolvePreset(state: OrbState, size: OrbSize) -> Resolved {
    let mode = stateToMode[state]!
    let preset = presets[mode]![size]!
    var opts = baseProfiles[mode.rawValue]!
    if preset.count != 1 { opts = scaleCounts(opts, preset.count) }
    if preset.size != 1 { opts = scaleRadii(opts, preset.size) }
    opts.merge(preset.extra) { _, new in new }
    return Resolved(mode: mode, speed: preset.speed, opts: opts)
}
