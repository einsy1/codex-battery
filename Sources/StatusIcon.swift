import AppKit

// Stable raw values are persisted, independently of translated display names.
enum StatusIconStyle: String, CaseIterable, Identifiable {
    case ring, bars, ghost
    var id: String { rawValue }
    var title: String {
        switch self { case .ring: return "能量环"; case .bars: return "五段能量条"; case .ghost: return "小幽灵" }
    }
    static func restored(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "statusIconStyle") ?? "") ?? .ring
    }
}

enum StatusIconRenderer {
    static func image(style: StatusIconStyle, remaining: Double?, phase: Double = 0, refreshing: Bool = false) -> NSImage {
        let fraction = remaining.map { min(1, max(0, $0 / 100)) }
        let image = NSImage(size: NSSize(width: 26, height: 20), flipped: false) { _ in
            func fill(_ alpha: CGFloat = 1) { NSColor.black.withAlphaComponent(alpha).setFill() }
            func stroke(_ alpha: CGFloat = 1) { NSColor.black.withAlphaComponent(alpha).setStroke() }
            switch style {
            case .ring:
                let center = NSPoint(x: 12.5, y: 10)
                func arc(_ amount: Double, alpha: CGFloat, width: CGFloat = 1.65) {
                    let path = NSBezierPath()
                    path.appendArc(withCenter: center, radius: 8, startAngle: 230, endAngle: 230 - 280 * amount, clockwise: true)
                    path.lineWidth = width; path.lineCapStyle = .round; stroke(alpha); path.stroke()
                }
                arc(1, alpha: 0.2)
                if let fraction, fraction > 0 { arc(fraction, alpha: 1) }
                if refreshing && phase > 0 && phase < 1 {
                    let a = (230 - 280 * phase) * .pi / 180
                    fill(); NSBezierPath(ovalIn: NSRect(x: center.x + 8 * cos(a) - 1.25, y: center.y + 8 * sin(a) - 1.25, width: 2.5, height: 2.5)).fill()
                }
                let command = "⌘" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black.withAlphaComponent(fraction == nil ? 0.45 : 1)]
                let size = command.size(withAttributes: attrs)
                command.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
            case .bars:
                for index in 0..<5 {
                    let rect = NSRect(x: 2 + Double(index) * 4.7, y: 3.5, width: 3.2, height: 13)
                    let path = NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6)
                    fill(0.18); path.fill()
                    if let fraction {
                        let segment = min(1, max(0, fraction * 5 - Double(index)))
                        if segment > 0 {
                            NSGraphicsContext.saveGraphicsState(); path.addClip()
                            fill(); NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * segment)).fill()
                            NSGraphicsContext.restoreGraphicsState()
                        }
                    }
                    if refreshing && phase > 0 && phase < 1 && Int(phase * 5) == index {
                        fill(0.55); NSBezierPath(ovalIn: NSRect(x: rect.midX - 0.8, y: 18, width: 1.6, height: 1.6)).fill()
                    }
                }
                if fraction == nil {
                    fill(0.7)
                    NSBezierPath(roundedRect: NSRect(x: 8, y: 9.3, width: 10, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
                }
            case .ghost:
                let bob = refreshing ? sin(phase * 2 * .pi) * 0.8 : 0
                let body = NSBezierPath()
                body.move(to: NSPoint(x: 4, y: 3 + bob))
                body.curve(to: NSPoint(x: 4, y: 11 + bob), controlPoint1: NSPoint(x: 4, y: 6 + bob), controlPoint2: NSPoint(x: 4, y: 8 + bob))
                body.curve(to: NSPoint(x: 21, y: 11 + bob), controlPoint1: NSPoint(x: 4, y: 21 + bob), controlPoint2: NSPoint(x: 21, y: 21 + bob))
                body.line(to: NSPoint(x: 21, y: 3 + bob))
                body.curve(to: NSPoint(x: 17, y: 3 + bob), controlPoint1: NSPoint(x: 20, y: 0.5 + bob), controlPoint2: NSPoint(x: 18, y: 0.5 + bob))
                body.curve(to: NSPoint(x: 12.5, y: 3 + bob), controlPoint1: NSPoint(x: 16, y: 0.5 + bob), controlPoint2: NSPoint(x: 13.5, y: 0.5 + bob))
                body.curve(to: NSPoint(x: 8, y: 3 + bob), controlPoint1: NSPoint(x: 11.5, y: 0.5 + bob), controlPoint2: NSPoint(x: 9, y: 0.5 + bob))
                body.curve(to: NSPoint(x: 4, y: 3 + bob), controlPoint1: NSPoint(x: 7, y: 0.5 + bob), controlPoint2: NSPoint(x: 5, y: 0.5 + bob))
                body.close()
                fill(0.2); body.fill()
                if let fraction {
                    NSGraphicsContext.saveGraphicsState(); body.addClip()
                    fill(0.95)
                    NSBezierPath(rect: NSRect(x: 2, y: 0, width: 22, height: 3 + 15 * fraction + bob)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                stroke(fraction == nil ? 0.45 : 0.9); body.lineWidth = 1; body.stroke()
                // Cut eyes out of the alpha mask: they stay legible in both menu-bar appearances.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
                fill()
                for x in [9.0, 16.0] {
                    if let fraction, fraction <= 0.25 {
                        let eye = NSBezierPath(); eye.move(to: NSPoint(x: x - 1.1, y: 11 + bob)); eye.line(to: NSPoint(x: x + 1.1, y: 10.5 + bob)); eye.lineWidth = 1.2; eye.lineCapStyle = .round; eye.stroke()
                    } else {
                        NSBezierPath(ovalIn: NSRect(x: x - 0.9, y: 10 + bob, width: 1.8, height: 2.8)).fill()
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = style.title
        return image
    }
}
