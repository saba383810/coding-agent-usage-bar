import AppKit

enum GaugeStyle {
    static func color(forPercent percent: Double?) -> NSColor {
        guard let percent else { return .systemGray }
        switch percent {
        case ..<70: return .systemGreen
        case ..<90: return .systemOrange
        default: return .systemRed
        }
    }

    // メニューバー用の円ゲージアイコン
    static func menuBarImage(percent: Double?, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth: CGFloat = 2.5
            let inset = lineWidth / 2 + 0.5
            let circleRect = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = circleRect.width / 2

            let background = NSBezierPath(ovalIn: circleRect)
            background.lineWidth = lineWidth
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            background.stroke()

            if let percent {
                let progress = min(max(percent, 0), 100) / 100
                if progress > 0 {
                    let arc = NSBezierPath()
                    // 12時位置から時計回り
                    arc.appendArc(
                        withCenter: center,
                        radius: radius,
                        startAngle: 90,
                        endAngle: 90 - 360 * progress,
                        clockwise: true
                    )
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    color(forPercent: percent).setStroke()
                    arc.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
