import Foundation
import SwiftUI

@main enum Main {
    static func main() {
        guard CommandLine.arguments.contains("--dump") else { return SofleApp.main() }
        // Prints what the app reads from the keyboard as JSON, to compare with config/sofle.keymap.
        let keyboard = Keyboard(), started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard (keyboard.source == .live && keyboard.levels.count == 2) || Date().timeIntervalSince(started) > 45 else { return }
            let dump: [String: Any] = [
                "source": "\(keyboard.source)", "output": keyboard.output.map { "\($0)" } ?? "unknown", "connected": keyboard.connected,
                "left": keyboard.levels[.left] ?? -1, "right": keyboard.levels[.right] ?? -1,
                "layers": keyboard.layers.map { ["name": $0.name, "bindings": $0.bindings] },
                "keys": keyboard.keys.map { [$0.x, $0.y, $0.w, $0.h, $0.r, $0.rx, $0.ry] },
            ]
            print(String(decoding: (try? JSONSerialization.data(withJSONObject: dump, options: [.sortedKeys])) ?? Data(), as: UTF8.self))
            exit(0)
        }
        RunLoop.main.run()
    }
}
