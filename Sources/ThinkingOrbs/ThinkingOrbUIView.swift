// The UIKit front end: a UIView drawing the same engine through draw(_:),
// the sibling of the AppKit ThinkingOrbView. A CADisplayLink drives frames
// and stops automatically while the view is windowless, hidden, transparent,
// scrolled outside its window, or the app is in the background — the UIKit
// analogue of the AppKit view's occlusion + clip-view plumbing. Reduce Motion
// shows the same static representative frame as the other two front ends.
//
// The engine's geometry is written for a y-up context (an unflipped NSView),
// so this view flips the CTM before handing the context over. Otherwise a
// mode with an up/down reading — the globe's scan meridian, the wave — would
// run mirrored against the same orb on the Mac.

#if canImport(UIKit) && !canImport(AppKit)
import UIKit
import QuartzCore

/// A dotted thought-orb loading indicator, UIKit edition.
///
/// ```swift
/// let orb = ThinkingOrbView(state: .working)            // 64pt orb
/// let inline = ThinkingOrbView(state: .searching, orbSize: .px20)
/// ```
///
/// The view sizes itself via `intrinsicContentSize`; when given a larger
/// frame it draws the orb centered.
public final class ThinkingOrbView: UIView {
    /// Which animation to show.
    public var state: OrbState {
        didSet {
            guard state != oldValue else { return }
            resolved = resolvePreset(state: state, size: orbSize)
            accessibilityLabel = state.label
            setNeedsDisplay()
        }
    }

    /// Tuned size preset — 64 or 20 points.
    public var orbSize: OrbSize {
        didSet {
            guard orbSize != oldValue else { return }
            resolved = resolvePreset(state: state, size: orbSize)
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// Theme mode; `auto` follows `traitCollection.userInterfaceStyle`.
    public var theme: OrbTheme {
        didSet { setNeedsDisplay() }
    }

    /// Ink colour. `nil` keeps the grayscale ink that follows `theme`; a
    /// colour drives the whole mark from one hue, depth carried on opacity,
    /// so the orb can match a host app's accent instead of black-on-white.
    public var tint: CGColor? {
        didSet { setNeedsDisplay() }
    }

    /// Animation speed multiplier on top of the preset's baked speed.
    public var speed: Double {
        didSet { setNeedsDisplay() }
    }

    /// Freeze the animation on the current frame.
    public var paused: Bool {
        didSet {
            updateRunning()
            setNeedsDisplay()
        }
    }

    /// Pins the orb to one clock position instead of following the shared epoch, and stops the
    /// display link. `paused` freezes on whichever frame happened to be current, which is a
    /// different picture on every launch; this is the same deterministic frame every time, so a
    /// screenshot fixture can hold the orb still and still match its baseline. Reduce Motion
    /// takes this path at 0.6 whether or not a host asked for it.
    public var staticFrameTime: Double? {
        didSet {
            guard staticFrameTime != oldValue else { return }
            updateRunning()
            setNeedsDisplay()
        }
    }

    private var resolved: Resolved
    private var displayLink: CADisplayLink?
    /// Tracked from notifications rather than read from `UIApplication.shared`,
    /// which is unavailable to app extensions linking this package.
    private var applicationIsForeground = true

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
        super.init(frame: CGRect(x: 0, y: 0, width: orbSize.rawValue, height: orbSize.rawValue))
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently
        accessibilityLabel = state.label
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityOptionsChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        displayLink?.invalidate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: orbSize.rawValue, height: orbSize.rawValue)
    }

    // --- run/stop plumbing --------------------------------------------

    private var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRunning()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateRunning()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // A view can join a window with a zero frame and receive its real size only when Auto
        // Layout runs. Re-check here so that case starts without waiting for another event.
        updateRunning()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.userInterfaceStyle
            != previousTraitCollection?.userInterfaceStyle else { return }
        setNeedsDisplay()
    }

    @objc private func accessibilityOptionsChanged() {
        updateRunning()
        setNeedsDisplay()
    }

    @objc private func applicationDidEnterBackground() {
        applicationIsForeground = false
        updateRunning()
    }

    @objc private func applicationWillEnterForeground() {
        applicationIsForeground = true
        updateRunning()
    }

    private func updateRunning() {
        let shouldRun = window != nil
            && applicationIsForeground
            && hasVisibleDrawingArea
            && !isHiddenOrHasHiddenAncestor
            && !paused
            && staticFrameTime == nil
            && !reduceMotion
        if shouldRun { start() } else { stop() }
    }

    /// `isHidden`/`alpha` say whether an ancestor is drawing at all; the window intersection
    /// additionally says whether a pixel of the result can currently land on screen — the
    /// UIKit reading of the AppKit view's `visibleRect`. Kept internal so a host regression
    /// test can pin the geometry without exposing profiler state as product API.
    var hasVisibleDrawingArea: Bool {
        guard let window, !bounds.isEmpty else { return false }
        return convert(bounds, to: window).intersects(window.bounds)
    }

    var isHiddenOrHasHiddenAncestor: Bool {
        var view: UIView? = self
        while let current = view {
            if current.isHidden || current.alpha <= 0.01 { return true }
            view = current.superview
        }
        return false
    }

    private func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        setNeedsDisplay()
    }

    // --- drawing --------------------------------------------------------

    public override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let dark: Bool
        switch theme {
        case .auto: dark = traitCollection.userInterfaceStyle == .dark
        case .dark: dark = true
        case .light: dark = false
        }
        let px = Double(orbSize.rawValue)
        // a pinned frame, or reduced motion → one static, deterministic frame
        let t: Double
        if let staticFrameTime {
            t = staticFrameTime
        } else if reduceMotion {
            t = 0.6
        } else {
            t = Date().timeIntervalSince(orbEpoch) * resolved.speed * speed
        }
        cg.saveGState()
        // UIKit hands over a y-down context; the engine draws y-up.
        cg.translateBy(x: 0, y: bounds.height)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: (bounds.width - px) / 2, y: (bounds.height - px) / 2)
        resolved.mode.draw(cg, px, t, dark, resolved.opts, tint)
        cg.restoreGState()
    }
}
#endif
