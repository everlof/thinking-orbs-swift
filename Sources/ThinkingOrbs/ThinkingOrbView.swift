// The AppKit front end: an NSView drawing the same engine through
// draw(_:). A display link (macOS 14+; 60Hz timer on 13) drives frames
// and stops automatically while the view is windowless, hidden, clipped out
// of a scroll viewport, or in an occluded window — the AppKit analogue of the original's
// IntersectionObserver + visibilitychange plumbing. Reduce Motion shows
// the same static representative frame as the SwiftUI view.

#if canImport(AppKit)
import AppKit
import QuartzCore

/// A dotted thought-orb loading indicator, AppKit edition.
///
/// ```swift
/// let orb = ThinkingOrbView(state: .working)            // 64pt orb
/// let inline = ThinkingOrbView(state: .searching, orbSize: .px20)
/// ```
///
/// The view sizes itself via `intrinsicContentSize`; when given a larger
/// frame it draws the orb centered.
public final class ThinkingOrbView: NSView {
    /// Which animation to show.
    public var state: OrbState {
        didSet {
            guard state != oldValue else { return }
            resolved = resolvePreset(state: state, size: orbSize)
            setAccessibilityLabel(state.label)
            needsDisplay = true
        }
    }

    /// Tuned size preset — 64 or 20 points.
    public var orbSize: OrbSize {
        didSet {
            guard orbSize != oldValue else { return }
            resolved = resolvePreset(state: state, size: orbSize)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Theme mode; `auto` follows `effectiveAppearance`.
    public var theme: OrbTheme {
        didSet { needsDisplay = true }
    }

    /// Ink colour. `nil` keeps the grayscale ink that follows `theme`; a
    /// colour drives the whole mark from one hue, depth carried on opacity,
    /// so the orb can match a host app's accent instead of black-on-white.
    public var tint: CGColor? {
        didSet { needsDisplay = true }
    }

    /// Animation speed multiplier on top of the preset's baked speed.
    public var speed: Double {
        didSet { needsDisplay = true }
    }

    /// Freeze the animation on the current frame.
    public var paused: Bool {
        didSet {
            updateRunning()
            needsDisplay = true
        }
    }

    private var resolved: Resolved
    private var displayLink: Any? // CADisplayLink, stored untyped for macOS 13
    private var fallbackTimer: Timer?
    private var liveScrollingAncestors: Set<ObjectIdentifier> = []

    public init(
        state: OrbState = .working,
        orbSize: OrbSize = .px64,
        theme: OrbTheme = .auto,
        speed: Double = 1,
        paused: Bool = false
    ) {
        self.state = state
        self.orbSize = orbSize
        self.theme = theme
        self.speed = speed
        self.paused = paused
        self.resolved = resolvePreset(state: state, size: orbSize)
        super.init(frame: NSRect(x: 0, y: 0, width: orbSize.rawValue, height: orbSize.rawValue))
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.state = .working
        self.orbSize = .px64
        self.theme = .auto
        self.speed = 1
        self.paused = false
        self.resolved = resolvePreset(state: .working, size: .px64)
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(state.label)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    // same coordinate language as the engine: origin top-left, y down
    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: orbSize.rawValue, height: orbSize.rawValue)
    }

    // --- run/stop plumbing --------------------------------------------

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        followClipViews()
        updateRunning()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        followClipViews()
        updateRunning()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateRunning()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateRunning()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func layout() {
        super.layout()
        // A view can join a window with a zero frame and receive its real size only when Auto
        // Layout runs. Re-check here so that case starts without waiting for a scroll event.
        updateRunning()
    }

    @objc private func occlusionChanged() {
        updateRunning()
    }

    @objc private func accessibilityOptionsChanged() {
        updateRunning()
        needsDisplay = true
    }

    @objc private func clipViewBoundsChanged() {
        updateRunning()
    }

    @objc private func liveScrollWillStart(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        liveScrollingAncestors.insert(ObjectIdentifier(scrollView))
        updateRunning()
    }

    @objc private func liveScrollDidEnd(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else { return }
        liveScrollingAncestors.remove(ObjectIdentifier(scrollView))
        updateRunning()
        needsDisplay = true
    }

    /// Follow every enclosing clip view, not just `enclosingScrollView`. A gallery or inspector
    /// can put one scroll surface inside another; moving the outer clip does not change the
    /// inner clip's bounds, but it can still take this view completely off screen.
    private func followClipViews() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSScrollView.willStartLiveScrollNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSScrollView.didEndLiveScrollNotification,
            object: nil
        )
        liveScrollingAncestors.removeAll(keepingCapacity: true)

        var ancestor = superview
        while let view = ancestor {
            if let clipView = view as? NSClipView {
                clipView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(clipViewBoundsChanged),
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
                if let scrollView = clipView.enclosingScrollView {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(liveScrollWillStart),
                        name: NSScrollView.willStartLiveScrollNotification,
                        object: scrollView
                    )
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(liveScrollDidEnd),
                        name: NSScrollView.didEndLiveScrollNotification,
                        object: scrollView
                    )
                }
            }
            ancestor = view.superview
        }
    }

    private func updateRunning() {
        let windowIsVisible = window.map { $0.occlusionState.contains(.visible) } ?? false
        let shouldRun = windowIsVisible
            && hasVisibleDrawingArea
            && !isHiddenOrHasHiddenAncestor
            && liveScrollingAncestors.isEmpty
            && !paused
            && !reduceMotion
        if shouldRun { start() } else { stop() }
    }

    /// `isHidden` says whether an ancestor participates in layout; `visibleRect` additionally
    /// says whether an enclosing clip view can currently show a pixel of the result. Kept
    /// internal so the host's regression test can pin the geometry without exposing profiler
    /// state as product API.
    var hasVisibleDrawingArea: Bool {
        !visibleRect.isEmpty && bounds.intersects(visibleRect)
    }

    var isSuppressedForLiveScroll: Bool {
        !liveScrollingAncestors.isEmpty
    }

    private func start() {
        guard displayLink == nil, fallbackTimer == nil else { return }
        if #available(macOS 14.0, *) {
            let link = self.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
        }
    }

    private func stop() {
        if #available(macOS 14.0, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func tick() {
        needsDisplay = true
    }

    // --- drawing --------------------------------------------------------

    public override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let dark: Bool
        switch theme {
        case .auto: dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .dark: dark = true
        case .light: dark = false
        }
        let px = Double(orbSize.rawValue)
        // reduced motion → one static, deterministic frame
        let t = reduceMotion ? 0.6 : Date().timeIntervalSince(orbEpoch) * resolved.speed * speed
        cg.saveGState()
        cg.translateBy(x: (bounds.width - px) / 2, y: (bounds.height - px) / 2)
        resolved.mode.draw(cg, px, t, dark, resolved.opts, tint)
        cg.restoreGState()
    }
}
#endif
