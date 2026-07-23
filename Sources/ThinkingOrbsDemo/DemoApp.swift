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

struct DemoView: View {
    @State private var dark = true
    @State private var speed = 1.0
    @State private var paused = false

    var body: some View {
        VStack(spacing: 28) {
            Grid(horizontalSpacing: 36, verticalSpacing: 24) {
                ForEach(OrbState.allCases, id: \.self) { state in
                    GridRow {
                        ThinkingOrb(state: state, speed: speed, paused: paused)
                        ThinkingOrb(state: state, size: .px20, speed: speed, paused: paused)
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
#else
@main
enum Main {
    static func main() {
        print("The demo app is macOS-only; the ThinkingOrbs library itself supports iOS 15+ and macOS 13+.")
    }
}
#endif
