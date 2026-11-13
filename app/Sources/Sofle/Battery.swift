import Foundation

struct Reading: Codable, Equatable { var t: Date, level: Int }

enum TimeLeft: Equatable {
    case estimating, charging, left(TimeInterval)

    // shortcut: one straight line over wall-clock time since the level last stopped rising, so nights with the
    // keyboard asleep count as use and the estimate runs long; switch to a rate over connected time if that matters.
    static func estimate(_ readings: [Reading], now: Date) -> TimeLeft {
        guard let last = readings.last else { return .estimating }
        var start = readings.count - 1
        while start > 0, readings[start - 1].level >= readings[start].level { start -= 1 }
        if start > 0, start == readings.count - 1 { return .charging }  // the newest reading went up
        let drop = readings[start].level - last.level, elapsed = now.timeIntervalSince(readings[start].t)
        guard drop >= 2, elapsed >= 30 * 60 else { return .estimating }
        return .left(Double(last.level) / Double(drop) * elapsed)
    }
}

/// The battery voltage behind ZMK's percentage. ZMK maps 3.45 V → 0 % and 4.2 V → 100 % in a straight line, 7.5 mV
/// per percent, so this is that line run backwards: exact to ±4 mV, except that 0 % and 100 % are open-ended.
enum Voltage {
    static func text(_ level: Int) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        switch level {
        case ...0: return "≤ \(3.45.formatted(format)) V"
        case 100...: return "≥ \(4.19.formatted(format)) V"
        default: return "≈ \(((Double(level) + 459.5) * 7.5 / 1000).formatted(format)) V"
        }
    }
}
