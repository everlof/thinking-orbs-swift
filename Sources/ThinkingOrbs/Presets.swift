// The shipped tunings: nine states × two sizes, ported verbatim from the
// upstream tuning session. `count`/`size` are multipliers over the base
// fine profiles; `speed` multiplies the shared clock.

import CoreGraphics
import Foundation

/// The nine shipped states — each a hand-tuned animation:
/// - `working`    — particles on tilted orbits
/// - `searching`  — a scan meridian sweeps a dotted globe
/// - `solving`    — bands scramble in quarter turns, then click back
/// - `listening`  — a waveform rolls through latitude rings
/// - `connecting` — a constellation wires itself, packets running the edges
/// - `weaving`    — three strands plait around the sphere
/// - `composing`  — an undulating multi-band sash
/// - `breathing`  — a face-on ring slowly morphing
/// - `shaping`    — a dotted outline morphs circle → triangle → square
public enum OrbState: String, CaseIterable, Sendable {
    case working, searching, solving, listening, connecting, weaving, composing, breathing, shaping

    /// Human-readable label, used as the orb's accessibility label.
    public var label: String {
        switch self {
        case .working: return "Working…"
        case .searching: return "Searching…"
        case .solving: return "Solving…"
        case .listening: return "Listening…"
        case .connecting: return "Connecting…"
        case .weaving: return "Weaving…"
        case .composing: return "Composing…"
        case .breathing: return "Breathing…"
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
    case orbits, globe, rubik, wave, web, braid, ribbon, ring, morph

    var draw: ModeDraw {
        switch self {
        case .orbits: return drawOrbits
        case .globe: return drawGlobe
        case .rubik: return drawRubik
        case .wave: return drawWave
        case .web: return drawWeb
        case .braid: return drawBraid
        case .ribbon, .ring: return drawRibbon
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
    .connecting: .web,
    .weaving: .braid,
    .composing: .ribbon,
    .breathing: .ring,
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
    .web: [
        .px64: Preset(speed: 3.315, count: 1.35, size: 0.95),
        .px20: Preset(speed: 6.63, count: 0.25, size: 1.52)
    ],
    .braid: [
        .px64: Preset(speed: 1.625, count: 0.5, size: 1),
        .px20: Preset(speed: 2.75, count: 0.1125, size: 1.36)
    ],
    .ribbon: [
        .px64: Preset(speed: 2.34, count: 0.25, size: 0.85, extra: ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
        .px20: Preset(speed: 3.12, count: 0.051, size: 1.073, extra: ["spin": 0, "bandMul": 4.94, "wobMul": 1])
    ],
    .ring: [
        .px64: Preset(speed: 3.24, count: 0.25, size: 0.956, extra: ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
        .px20: Preset(speed: 3.78, count: 0.028, size: 1.622, extra: ["spin": 0, "bandMul": 3.968, "wobMul": 0.565])
    ],
    .morph: [
        .px64: Preset(speed: 2.405, count: 0.702, size: 0.395, extra: ["spread": 1.45]),
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
