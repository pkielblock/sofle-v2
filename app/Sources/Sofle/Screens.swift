import AppKit

/// The two 128x32 OLEDs, drawn like ZMK's stock status screen (zmk app/src/display/status_screen.c and its widgets):
/// output top left, battery top right, layer bottom left on the left half; connection and battery on the right half.
/// SF Symbols stand in for LVGL's icon font.
enum Screens {
    private enum Item { case symbol(String), text(String) }

    /// - output: what the left half is typing on, when known. `linked`: this Mac is connected to it over Bluetooth.
    static func left(output: Keyboard.Transport?, linked: Bool, level: Int?, layer: String) -> CGImage {
        render {
            switch output {
            case .usb: row([.symbol("cable.connector")], size: 10, y: 17)
            // ZMK also prints the profile number here; the keyboard doesn't report it, so it's left out.
            default: row([.symbol("wifi"), .symbol(linked ? "checkmark" : "xmark")], size: 13, y: 17)
            }
            if let level { row((output == .usb ? [.symbol("bolt.fill")] : []) + [.symbol(battery(level))], size: 13, y: 17, trailing: true) }
            row([.symbol("keyboard"), .text(layer)], size: 10, y: 1)
        }
    }

    /// nil level: the right half isn't answering.
    static func right(level: Int?) -> CGImage {
        render {
            row([.symbol("wifi"), .symbol(level == nil ? "xmark" : "checkmark")], size: 13, y: 17)
            if let level { row([.symbol(battery(level))], size: 13, y: 17, trailing: true) }
        }
    }

    static let off = render {}

    /// Same steps as zmk's battery_status.c.
    private static func battery(_ level: Int) -> String {
        level > 95 ? "battery.100" : level > 65 ? "battery.75" : level > 35 ? "battery.50" : level > 5 ? "battery.25" : "battery.0"
    }

    private static func row(_ items: [Item], size: CGFloat, y: CGFloat, trailing: Bool = false) {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let pieces: [(NSSize, (NSPoint) -> Void)] = items.compactMap { item in
            switch item {
            case .text(let text):
                let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
                return (string.size(), { string.draw(at: $0) })
            case .symbol(let name):
                let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
                guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
                // Filled through the symbol's alpha: drawn directly, a symbol takes the system's label color.
                return (image.size, { origin in
                    guard let context = NSGraphicsContext.current?.cgContext, let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                    let rect = NSRect(origin: origin, size: image.size)
                    context.saveGState()
                    context.clip(to: rect, mask: mask)
                    context.setFillColor(gray: 0, alpha: 1)
                    context.fill(rect)
                    context.restoreGState()
                })
            }
        }
        let gap: CGFloat = 3, height: CGFloat = 14  // each row is a 14 px band
        var x = trailing ? 128 - pieces.map(\.0.width).reduce(0, +) - gap * CGFloat(pieces.count - 1) : 0
        for (size, draw) in pieces {
            draw(NSPoint(x: x.rounded(), y: (y + (height - size.height) / 2).rounded()))
            x += size.width + gap
        }
    }

    /// Draws at 128x32 in black on white (the color symbols draw in), then makes every dark pixel a lit one:
    /// each pixel is fully on or off, like the real one-bit panel.
    private static func render(_ draw: () -> Void) -> CGImage {
        let context = CGContext(data: nil, width: 128, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 128, height: 32).fill()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: 128 * 32)
        for i in 0..<128 * 32 { pixels[i] = pixels[i] < 128 ? 255 : 0 }
        return context.makeImage()!
    }
}
