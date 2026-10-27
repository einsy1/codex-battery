import AppKit
@main struct IconTests {
    static func main() throws {
        let suite = "CodexBattery.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); print("PASS \(label)") }
        check(StatusIconStyle.restored(from: defaults) == .ring, "new or migrated installation defaults to ring")
        for style in StatusIconStyle.allCases {
            defaults.set(style.rawValue, forKey: "statusIconStyle")
            check(StatusIconStyle.restored(from: UserDefaults(suiteName: suite)!) == style, "\(style.rawValue) survives preferences reload")
        }
        defaults.set("retired-style", forKey: "statusIconStyle")
        check(StatusIconStyle.restored(from: defaults) == .ring, "unknown stored style falls back safely")
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in StatusIconStyle.allCases {
            var variants: [Data] = []
            for value: Double? in [nil, 0, 10, 25, 77, 100] {
                let image = StatusIconRenderer.image(style: style, remaining: value)
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 104, pixelsHigh: 80, bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSGraphicsContext.current?.cgContext.scaleBy(x: 4, y: 4)
                image.draw(in: NSRect(x:0,y:0,width:26,height:20))
                NSGraphicsContext.restoreGraphicsState()
                let data = bitmap.representation(using:.png,properties:[:])!
                variants.append(data)
                let label = value.map{String(Int($0))} ?? "unknown"
                try data.write(to:directory.appendingPathComponent("\(style.rawValue)-\(label).png"))
            }
            check(Set(variants).count == variants.count, "\(style.rawValue) visibly distinguishes unknown, empty, low, partial, full")
        }
    }
}
