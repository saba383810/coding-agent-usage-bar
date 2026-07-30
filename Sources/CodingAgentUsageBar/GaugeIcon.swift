import AppKit

// メニューバーに合成描画する 1 個分のゲージ
struct MenuBarGauge: Identifiable {
    let id: String
    // どちらのゲージかを示す識別子。アイコン表示なら symbolName、そうでなければ text
    let text: String?
    let symbolName: String?
    let percent: Double?

    var hasLabel: Bool { text != nil || symbolName != nil }
}

enum GaugeStyle {
    static func color(forPercent percent: Double?) -> NSColor {
        guard let percent else { return .systemGray }
        switch percent {
        case ..<70: return .systemGreen
        case ..<90: return .systemOrange
        default: return .systemRed
        }
    }

    // メニューバー用の円ゲージアイコン (パーセントは SwiftUI 側の Text で出す)
    static func menuBarImage(percent: Double?, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawGauge(percent: percent, in: rect.insetBy(dx: 0.5, dy: 0.5))
            return true
        }
        image.isTemplate = false
        return image
    }

    // 複数ゲージ / 識別子つきの表示用。
    // MenuBarExtra の label は Image 1 枚 + Text 1 個しか反映されないため、
    // 識別子とパーセントまで含めて 1 枚の画像に描く。
    static func menuBarImage(gauges: [MenuBarGauge], height: CGFloat = 16) -> NSImage {
        let textFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let gaugeSize: CGFloat = 13
        let innerSpacing: CGFloat = 2.5
        let itemSpacing: CGFloat = 7
        let horizontalPadding: CGFloat = 1.5

        struct Piece {
            let text: String?
            let symbol: NSImage?
            let labelWidth: CGFloat
            let value: String
            let valueWidth: CGFloat
            let width: CGFloat
        }

        let pieces: [Piece] = gauges.map { gauge in
            let symbol = gauge.symbolName.flatMap { symbolImage($0) }
            let text = symbol == nil ? gauge.text : nil
            let labelWidth: CGFloat = {
                if let symbol { return symbol.size.width }
                if let text { return textSize(text, font: textFont).width }
                return 0
            }()
            let value = gauge.percent.map { "\(Int($0))%" } ?? "–"
            let valueWidth = textSize(value, font: valueFont).width
            var width = gaugeSize + innerSpacing + valueWidth
            if labelWidth > 0 { width += labelWidth + innerSpacing }
            return Piece(
                text: text,
                symbol: symbol,
                labelWidth: labelWidth,
                value: value,
                valueWidth: valueWidth,
                width: width
            )
        }
        // 文字のサイドベアリングで端が欠けないよう左右に余白を取る
        let totalWidth = pieces.reduce(0) { $0 + $1.width }
            + CGFloat(max(pieces.count - 1, 0)) * itemSpacing
            + horizontalPadding * 2

        let image = NSImage(
            size: NSSize(width: max(totalWidth, 1), height: height),
            flipped: false
        ) { _ in
            var x: CGFloat = horizontalPadding
            for (piece, gauge) in zip(pieces, gauges) {
                if let symbol = piece.symbol {
                    let rect = NSRect(
                        x: x,
                        y: (height - symbol.size.height) / 2,
                        width: symbol.size.width,
                        height: symbol.size.height
                    )
                    drawSymbol(symbol, in: rect)
                    x += piece.labelWidth + innerSpacing
                } else if let text = piece.text {
                    drawText(text, font: textFont, x: x, height: height)
                    x += piece.labelWidth + innerSpacing
                }
                let gaugeRect = NSRect(
                    x: x + 0.5,
                    y: (height - gaugeSize) / 2 + 0.5,
                    width: gaugeSize - 1,
                    height: gaugeSize - 1
                )
                drawGauge(percent: gauge.percent, in: gaugeRect)
                x += gaugeSize + innerSpacing
                drawText(piece.value, font: valueFont, x: x, height: height)
                x += piece.valueWidth + itemSpacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func symbolImage(_ name: String, pointSize: CGFloat = 9.5) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        return image.withSymbolConfiguration(config)
    }

    // SF Symbol は template 画像なので、そのまま draw せずラベル色を乗せる
    private static func drawSymbol(_ symbol: NSImage, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        symbol.draw(in: rect)
        NSColor.labelColor.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawGauge(percent: Double?, in rect: NSRect) {
        let lineWidth: CGFloat = 2.5
        let circleRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = circleRect.width / 2

        let background = NSBezierPath(ovalIn: circleRect)
        background.lineWidth = lineWidth
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
        background.stroke()

        guard let percent else { return }
        let progress = min(max(percent, 0), 100) / 100
        guard progress > 0 else { return }
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

    private static func attributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    private static func textSize(_ text: String, font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: attributes(font: font))
    }

    private static func drawText(_ text: String, font: NSFont, x: CGFloat, height: CGFloat) {
        let attrs = attributes(font: font)
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: NSPoint(x: x, y: (height - size.height) / 2),
            withAttributes: attrs
        )
    }
}
