// The ThinkingOrb view. One shared clock keeps every mounted orb in
// phase; TimelineView(.animation) drives the frames and pauses drawing
// automatically while the view is invisible. Reduced-motion users get a
// static representative frame that still follows the live theme.

import SwiftUI

/// A dotted thought-orb loading indicator for AI / agent interfaces.
///
/// ```swift
/// ThinkingOrb(state: .working)                  // 64pt chat-avatar orb
/// ThinkingOrb(state: .searching, size: .px20)   // 20pt inline orb
/// ```
public struct ThinkingOrb: View {
    private let state: OrbState
    private let size: OrbSize
    private let theme: OrbTheme
    private let speed: Double
    private let paused: Bool
    private let resolved: Resolved

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - state: Which animation to show.
    ///   - size: Tuned size preset — 64 or 20 points.
    ///   - theme: Theme mode; `auto` follows the environment color scheme.
    ///   - speed: Animation speed multiplier on top of the preset's baked speed.
    ///   - paused: Freeze the animation on the current frame.
    public init(
        state: OrbState = .working,
        size: OrbSize = .px64,
        theme: OrbTheme = .auto,
        speed: Double = 1,
        paused: Bool = false
    ) {
        self.state = state
        self.size = size
        self.theme = theme
        self.speed = speed
        self.paused = paused
        self.resolved = resolvePreset(state: state, size: size)
    }

    public var body: some View {
        let px = Double(size.rawValue)
        let effSpeed = resolved.speed * speed
        let dark = theme == .auto ? colorScheme == .dark : theme == .dark
        let still = paused || reduceMotion

        TimelineView(.animation(minimumInterval: nil, paused: still)) { timeline in
            Canvas { ctx, _ in
                // reduced motion → one static, deterministic frame
                let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSince(orbEpoch) * effSpeed
                ctx.withCGContext { cg in
                    resolved.mode.draw(cg, px, t, dark, resolved.opts)
                }
            }
        }
        .frame(width: px, height: px)
        .accessibilityLabel(state.label)
    }
}

/// A single deterministic frame of an orb — for previews, snapshots and
/// widgets, or anywhere an animation clock isn't available.
public struct ThinkingOrbFrame: View {
    private let size: OrbSize
    private let theme: OrbTheme
    private let time: Double
    private let resolved: Resolved

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter time: Clock time in seconds; the preset's baked speed
    ///   is applied on top, matching the animated view at the same instant.
    public init(state: OrbState = .working, size: OrbSize = .px64, theme: OrbTheme = .auto, time: Double = 0.6) {
        self.size = size
        self.theme = theme
        self.time = time
        self.resolved = resolvePreset(state: state, size: size)
    }

    public var body: some View {
        let px = Double(size.rawValue)
        let dark = theme == .auto ? colorScheme == .dark : theme == .dark
        Canvas { ctx, _ in
            ctx.withCGContext { cg in
                resolved.mode.draw(cg, px, time * resolved.speed, dark, resolved.opts)
            }
        }
        .frame(width: px, height: px)
    }
}

#Preview("All states") {
    VStack(spacing: 24) {
        ForEach(OrbState.allCases, id: \.self) { state in
            HStack(spacing: 24) {
                ThinkingOrb(state: state)
                ThinkingOrb(state: state, size: .px20)
                Text(state.label)
                Spacer()
            }
        }
    }
    .padding(32)
}
