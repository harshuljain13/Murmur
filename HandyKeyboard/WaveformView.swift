import UIKit

/// A clean, real-time scrolling waveform. Feed it normalized levels (0...1)
/// via `push(_:)` while recording; it renders symmetric rounded bars that
/// scroll right-to-left.
final class WaveformView: UIView {

    private var levels: [CGFloat] = []
    private let maxBars = 46
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3
    private let minBarHeight: CGFloat = 3

    var barColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Add a new level sample (0...1). Oldest samples scroll off the left.
    func push(_ level: CGFloat) {
        let clamped = max(0, min(1, level))
        levels.append(clamped)
        if levels.count > maxBars { levels.removeFirst(levels.count - maxBars) }
        setNeedsDisplay()
    }

    /// Clear the waveform (e.g. when recording stops).
    func reset() {
        levels.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let midY = rect.height / 2
        let step = barWidth + barSpacing
        // Right-align so newest bar is on the right edge
        let totalWidth = CGFloat(levels.count) * step
        var x = rect.width - totalWidth

        ctx.setFillColor(barColor.cgColor)

        for level in levels {
            let h = max(minBarHeight, level * (rect.height - 6))
            let barRect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: barWidth / 2)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            x += step
        }
    }
}
