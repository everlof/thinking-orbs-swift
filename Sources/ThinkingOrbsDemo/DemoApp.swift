// Demo gallery for the ThinkingOrbs package. Run with:
//
//   swift run ThinkingOrbsDemo               # live animated gallery
//   swift run ThinkingOrbsDemo --snapshot p  # render static frames to p.png
//
#if os(macOS)
import AppKit
import SwiftUI
import ThinkingOrbs

@main
@MainActor
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            renderSnapshot(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--snapshot-appkit"), args.count > i + 1 {
            renderAppKitSnapshot(to: args[i + 1])
            return
        }
        DemoApp.main()
    }
}

struct DemoApp: App {
    init() {
        // activate properly when launched via `swift run` (no app bundle)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Thinking Orbs") {
            DemoView()
        }
        .windowResizability(.contentSize)
    }
}

/// Hosts the AppKit ThinkingOrbView inside the SwiftUI demo grid.
struct AppKitOrb: NSViewRepresentable {
    var state: OrbState
    var size: OrbSize = .px64
    var speed: Double = 1
    var paused: Bool = false

    func makeNSView(context: Context) -> ThinkingOrbView {
        ThinkingOrbView(state: state, orbSize: size, speed: speed, paused: paused)
    }

    func updateNSView(_ view: ThinkingOrbView, context: Context) {
        view.state = state
        view.orbSize = size
        view.speed = speed
        view.paused = paused
    }
}

struct DemoView: View {
    @State private var dark = true
    @State private var speed = 1.0
    @State private var paused = false

    var body: some View {
        VStack(spacing: 28) {
            Grid(horizontalSpacing: 36, verticalSpacing: 24) {
                GridRow {
                    ForEach(["SwiftUI", "AppKit", "SwiftUI", "AppKit"], id: \.self) { caption in
                        Text(caption)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(width: 1, height: 1)
                }
                ForEach(OrbState.allCases, id: \.self) { state in
                    GridRow {
                        ThinkingOrb(state: state, speed: speed, paused: paused)
                        AppKitOrb(state: state, speed: speed, paused: paused)
                            .frame(width: 64, height: 64)
                        ThinkingOrb(state: state, size: .px20, speed: speed, paused: paused)
                        AppKitOrb(state: state, size: .px20, speed: speed, paused: paused)
                            .frame(width: 20, height: 20)
                        Text(state.label)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .gridColumnAlignment(.leading)
                    }
                }
            }
            HStack(spacing: 20) {
                Toggle("Dark", isOn: $dark)
                Toggle("Paused", isOn: $paused)
                Slider(value: $speed, in: 0.25...3) {
                    Text("Speed")
                }
                .frame(width: 160)
                Text(String(format: "%.2f×", speed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(40)
        .frame(minWidth: 420)
        .background(dark ? Color(white: 0.09) : Color(white: 0.98))
        .preferredColorScheme(dark ? .dark : .light)
    }
}

// --- snapshot: a grid of deterministic frames, both themes ------------

@MainActor
private func renderSnapshot(to path: String) {
    let times: [Double] = [0.6, 1.3, 2.1, 3.4]

    func column(dark: Bool) -> some View {
        VStack(spacing: 16) {
            ForEach(OrbState.allCases, id: \.self) { state in
                HStack(spacing: 16) {
                    Text(state.rawValue)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(dark ? Color.white : .black)
                        .frame(width: 80, alignment: .leading)
                    ForEach(times, id: \.self) { t in
                        ThinkingOrbFrame(state: state, theme: dark ? .dark : .light, time: t)
                    }
                    ForEach(times, id: \.self) { t in
                        ThinkingOrbFrame(state: state, size: .px20, theme: dark ? .dark : .light, time: t)
                    }
                }
            }
        }
        .padding(24)
        .background(dark ? Color(white: 0.09) : Color(white: 0.98))
    }

    let view = HStack(spacing: 0) {
        column(dark: false)
        column(dark: true)
    }

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("snapshot: PNG encode failed\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: path.hasSuffix(".png") ? path : path + ".png")
    do {
        try png.write(to: url)
        print("wrote \(url.path)")
    } catch {
        FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        exit(1)
    }
}
// --- snapshot: the AppKit views rendered windowless via cacheDisplay --

@MainActor
private func renderAppKitSnapshot(to path: String) {
    let states = OrbState.allCases
    // three clock multipliers so one pass catches several morph phases
    let speeds: [Double] = [1, 0.37, 0.13]
    let rowH = 88.0
    let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 480, height: rowH * Double(states.count)))
    root.wantsLayer = true
    root.layer?.backgroundColor = CGColor(gray: 0.09, alpha: 1)

    for (i, state) in states.enumerated() {
        let y = Double(i) * rowH + 12
        for (j, s) in speeds.enumerated() {
            let v64 = ThinkingOrbView(state: state, orbSize: .px64, theme: .dark, speed: s)
            v64.frame = NSRect(x: 20 + Double(j) * 84, y: y, width: 64, height: 64)
            root.addSubview(v64)
            let v20 = ThinkingOrbView(state: state, orbSize: .px20, theme: .dark, speed: s)
            v20.frame = NSRect(x: 300 + Double(j) * 40, y: y + 22, width: 20, height: 20)
            root.addSubview(v20)
        }
    }

    guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
        FileHandle.standardError.write(Data("snapshot: no bitmap rep\n".utf8))
        exit(1)
    }
    root.cacheDisplay(in: root.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("snapshot: PNG encode failed\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: path.hasSuffix(".png") ? path : path + ".png")
    do {
        try png.write(to: url)
        print("wrote \(url.path)")
    } catch {
        FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        exit(1)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
#else
@main
enum Main {
    static func main() {
        print("The demo app is macOS-only; the ThinkingOrbs library itself supports iOS 15+ and macOS 13+.")
    }
}
#endif
