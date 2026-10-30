import AppKit
import CarbonCore
import SwiftUI

/// Carbon's menu bar item. Made by hand rather than as a `MenuBarExtra`: its mic meter moves three layers, where a
/// `MenuBarExtra` label would swap the item's image on every level, which cost about 18% of a core
/// (docs/research/menu-bar-mic-meter-performance.md).
@MainActor
final class StatusItem {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let meter = MicMeterView()
    private let meterOffset: NSLayoutConstraint
    private let model: AppModel

    init(model: AppModel, updater: Updater) {
        self.model = model
        item.menu = NSHostingMenu(rootView: MenuBarMenu(model: model, updater: updater))
        let button = item.button!
        button.imagePosition = .imageOnly
        // Hands the model SwiftUI's `openWindow`, which only a view can give.
        let handover = NSHostingView(rootView: Color.clear.modifier(HandsOpenWindowToModel(model: model)))
        handover.frame = .zero
        button.addSubview(handover)
        meter.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(meter)
        meterOffset = meter.centerXAnchor.constraint(equalTo: button.centerXAnchor)
        NSLayoutConstraint.activate([
            meterOffset,
            meter.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            meter.widthAnchor.constraint(equalToConstant: MicMeterView.side),
            meter.heightAnchor.constraint(equalToConstant: MicMeterView.side),
        ])
        model.recorder.onMicLevel = { [meter] in meter.hear($0) }
        update()
    }

    var isVisible: Bool {
        get { item.isVisible }
        set { item.isVisible = newValue }
    }

    /// Redraws the item when a Meeting goes live or ends, or its language changes. The meter never redraws it.
    private func update() {
        let (isLive, language) = withObservationTracking {
            (model.isLive, model.liveMeetingLanguage)
        } onChange: {
            Task { @MainActor [weak self] in self?.update() }
        }
        guard let button = item.button else { return }
        let image = isLive ? Self.liveImage(badge: language?.badge) : NSImage(named: "MenuBarIdle")!
        button.image = image
        button.setAccessibilityLabel(
            isLive ? language.map { "Carbon, transcribing in \($0.name)" } ?? "Carbon, transcribing" : "Carbon")
        // The meter sits on the image's first 18 pt, which the button centers.
        meterOffset.constant = (MicMeterView.side - image.size.width) / 2
        if meter.isHidden == isLive { meter.reset() }
        meter.isHidden = !isLive
    }

    /// Room for the meter, then the Meeting Language's badge cut out of a filled capsule, as a template image.
    private static func liveImage(badge: String?) -> NSImage {
        let side = MicMeterView.side
        guard let badge else { return NSImage(size: NSSize(width: side, height: side)) }
        let text = NSAttributedString(string: badge, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold)])
        let textSize = text.size()
        let capsule = NSRect(x: side, y: 3, width: ceil(textSize.width) + 8, height: 12)
        let image = NSImage(size: NSSize(width: capsule.maxX, height: side), flipped: false) { _ in
            NSBezierPath(roundedRect: capsule, xRadius: 6, yRadius: 6).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            text.draw(at: NSPoint(x: capsule.midX - textSize.width / 2, y: capsule.midY - textSize.height / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Three vertical bars, as heavy as SF Symbols' Regular `waveform`, that follow the mic: the middle bar the last
/// level, the outer ones the two before, so the meter ripples outward. They jump to each level without animating:
/// a Core Animation tween makes WindowServer redraw the menu bar at the display's refresh rate, about 14% of a core
/// more, where ten jumps a second cost nothing measurable. In silence they rest as 2 pt dots and nothing is committed.
private final class MicMeterView: NSView {
    static let side: CGFloat = 18
    private let bars = (0..<3).map { _ in CALayer() }
    private var history: [Float] = [0, 0, 0]

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        for (index, bar) in bars.enumerated() {
            bar.cornerRadius = 1
            bar.position = CGPoint(x: 5 + CGFloat(index) * 4, y: Self.side / 2)
            bar.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func hear(_ level: Float) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Reduce Motion: a still waveform that only says Carbon is transcribing.
            history = [0.8, 0.4, 0.4]
        } else {
            // Falls at most by half a level at a time, like a VU meter, so silence settles in steps.
            history = [max(level, history[0] / 2)] + history.dropLast()
        }
        move()
    }

    func reset() {
        history = [0, 0, 0]
        move()
    }

    private func move() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, level) in zip(bars, [history[1], history[0], history[2]]) {
            // Half-point steps: a change too small to see commits nothing.
            let height = ((2 + CGFloat(level) * 10) * 2).rounded() / 2
            if bar.bounds.height != height { bar.bounds.size.height = height }
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        recolor()
    }

    /// Layers take no template tint: color them as the menu bar's text.
    private func recolor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars { bar.backgroundColor = color }
            CATransaction.commit()
        }
    }
}
