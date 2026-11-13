import Foundation

// ZMK Studio RPC: protobuf messages (zmkfirmware/zmk-studio-messages) in SOF/ESC/EOF frames
// (zmk app/src/studio/msg_framing.h). Hand-rolled because the app needs three requests and three responses.

enum Framing {
    static let sof: UInt8 = 0xAB, esc: UInt8 = 0xAC, eof: UInt8 = 0xAD

    static func encode(_ payload: [UInt8]) -> [UInt8] {
        [sof] + payload.flatMap { [sof, esc, eof].contains($0) ? [esc, $0] : [$0] } + [eof]
    }

    struct Decoder {
        private var buffer: [UInt8] = [], inFrame = false, escaped = false

        /// Returns a payload when `byte` closes a frame.
        mutating func feed(_ byte: UInt8) -> [UInt8]? {
            if !inFrame {
                if byte == Framing.sof { inFrame = true; buffer = [] }
                return nil
            }
            if escaped { escaped = false; buffer.append(byte); return nil }
            switch byte {
            case Framing.esc: escaped = true
            case Framing.eof: inFrame = false; return buffer
            case Framing.sof: buffer = []  // a frame started before the last one ended: drop the partial one
            default: buffer.append(byte)
            }
            return nil
        }
    }
}

enum PB {
    enum Value { case varint(UInt64), bytes([UInt8]) }

    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat { out.append(UInt8(v & 0x7F) | (v > 0x7F ? 0x80 : 0)); v >>= 7 } while v > 0
        return out
    }
    static func field(_ n: UInt64, _ v: UInt64) -> [UInt8] { varint(n << 3) + varint(v) }
    static func field(_ n: UInt64, _ b: [UInt8]) -> [UInt8] { varint(n << 3 | 2) + varint(UInt64(b.count)) + b }
}

/// One decoded protobuf message. The bytes come from a device, so decoding stops at the first field it can't read.
struct Message {
    private(set) var fields: [(n: Int, v: PB.Value)] = []

    init(_ b: [UInt8]) {
        var i = 0
        func varint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count, shift < 64 {
                let byte = b[i]; i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return v }
                shift += 7
            }
            return nil
        }
        while i < b.count, let key = varint() {
            switch key & 7 {
            case 0:
                guard let v = varint() else { return }
                fields.append((Int(key >> 3), .varint(v)))
            case 2:
                guard let n = varint(), n <= UInt64(b.count - i) else { return }
                fields.append((Int(key >> 3), .bytes(Array(b[i..<i + Int(n)]))))
                i += Int(n)
            default: return
            }
        }
    }

    func uint(_ n: Int) -> UInt64 {
        for f in fields where f.n == n { if case .varint(let v) = f.v { return v } }
        return 0
    }
    /// sint32 (zigzag).
    func sint(_ n: Int) -> Int { let v = uint(n); return Int(Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1)) }
    func all(_ n: Int) -> [Message] {
        fields.compactMap { if $0.n == n, case .bytes(let b) = $0.v { return Message(b) } else { return nil } }
    }
    func sub(_ n: Int) -> Message? { all(n).first }
    func string(_ n: Int) -> String {
        for f in fields where f.n == n { if case .bytes(let b) = f.v { return String(decoding: b, as: UTF8.self) } }
        return ""
    }
}

struct KeyBinding: Equatable { var behavior: Int, param1: UInt32, param2: UInt32 }

/// Key units and degrees, as in ZMK's physical layouts.
struct KeyPosition: Equatable { var x, y, w, h, r, rx, ry: Double }

/// The only requests this app can build, and every one of them reads. Nothing here sets, saves, discards or resets.
enum StudioRequest {
    case keymap, physicalLayouts, behaviorDetails(Int)

    func encode(id: UInt64) -> [UInt8] {
        let body: [UInt8]
        switch self {
        case .keymap: body = PB.field(5, PB.field(1, 1))                                      // keymap.get_keymap
        case .physicalLayouts: body = PB.field(5, PB.field(6, 1))                             // keymap.get_physical_layouts
        case .behaviorDetails(let b): body = PB.field(4, PB.field(2, PB.field(1, UInt64(b)))) // behaviors.get_behavior_details
        }
        return PB.field(1, id) + body
    }
}

enum StudioResponse {
    case keymap([(name: String, bindings: [KeyBinding])])
    case physicalLayout([KeyPosition])
    case behavior(id: Int, name: String)
    case error

    /// nil for notifications, which carry no request id.
    static func decode(_ bytes: [UInt8]) -> (id: UInt64, response: StudioResponse)? {
        guard let rr = Message(bytes).sub(1) else { return nil }
        let id = rr.uint(1)
        if let keymap = rr.sub(5)?.sub(1) {
            return (id, .keymap(keymap.all(1).map { layer in
                (layer.string(2), layer.all(3).map {
                    KeyBinding(behavior: $0.sint(1), param1: UInt32(truncatingIfNeeded: $0.uint(2)), param2: UInt32(truncatingIfNeeded: $0.uint(3)))
                })
            }))
        }
        if let layouts = rr.sub(5)?.sub(6) {
            let all = layouts.all(2), active = Int(layouts.uint(1))
            let keys = (all.indices.contains(active) ? all[active] : all.first)?.all(2) ?? []
            func u(_ m: Message, _ n: Int) -> Double { Double(m.sint(n)) / 100 }
            return (id, .physicalLayout(keys.map {
                KeyPosition(x: u($0, 3), y: u($0, 4), w: u($0, 1), h: u($0, 2), r: u($0, 5), rx: u($0, 6), ry: u($0, 7))
            }))
        }
        if let b = rr.sub(4)?.sub(2) { return (id, .behavior(id: Int(b.uint(1)), name: b.string(2))) }
        return (id, .error)
    }
}
