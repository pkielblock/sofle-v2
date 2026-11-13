import Foundation

/// Names for bindings. `binding` is a port of tools/studio-to-keymap.ts (Studio binding → keymap text);
/// `legend` turns keymap text into what goes on a keycap.
enum Labels {
    static let keys: [UInt32: String] = {
        var k: [UInt32: String] = [
            0x28: "RET", 0x29: "ESC", 0x2a: "BSPC", 0x2b: "TAB", 0x2c: "SPACE", 0x2d: "MINUS", 0x2e: "EQUAL", 0x2f: "LBKT", 0x30: "RBKT",
            0x31: "BSLH", 0x33: "SEMI", 0x34: "SQT", 0x35: "GRAVE", 0x36: "COMMA", 0x37: "DOT", 0x38: "FSLH", 0x39: "CAPS",
            0x46: "PSCRN", 0x47: "SLCK", 0x48: "PAUSE_BREAK", 0x49: "INS", 0x4a: "HOME", 0x4b: "PG_UP", 0x4c: "DEL", 0x4d: "END", 0x4e: "PG_DN",
            0x4f: "RIGHT", 0x50: "LEFT", 0x51: "DOWN", 0x52: "UP", 0x65: "K_CMENU", 0x7a: "K_UNDO", 0x7b: "K_CUT", 0x7c: "K_COPY", 0x7d: "K_PASTE",
            0xe0: "LCTRL", 0xe1: "LSHFT", 0xe2: "LALT", 0xe3: "LGUI", 0xe4: "RCTRL", 0xe5: "RSHFT", 0xe6: "RALT", 0xe7: "RGUI",
        ]
        for i in 0..<26 { k[0x04 + UInt32(i)] = String(UnicodeScalar(UInt8(65 + i))) }
        for i in 1...9 { k[0x1d + UInt32(i)] = "N\(i)" }
        k[0x27] = "N0"
        for i in 1...12 { k[0x39 + UInt32(i)] = "F\(i)" }
        return k
    }()
    static let consumer: [UInt32: String] = [0xe2: "C_MUTE", 0xe9: "C_VOL_UP", 0xea: "C_VOL_DN", 0xcd: "C_PP", 0xb5: "C_NEXT", 0xb6: "C_PREV"]
    static let mods = ["LC", "LS", "LA", "LG", "RC", "RS", "RA", "RG"]
    static let modNames = ["LCTRL", "LSHFT", "LALT", "LGUI", "RCTRL", "RSHFT", "RALT", "RGUI"]
    static let bluetooth = ["BT_CLR", "BT_NXT", "BT_PRV", "BT_SEL", "BT_CLR_ALL", "BT_DISC"]

    /// HID usage (modifiers << 24 | page << 16 | id) → ZMK key name, e.g. "LA(S)". nil when unknown.
    static func key(_ usage: UInt32) -> String? {
        let m = usage >> 24, page = (usage >> 16) & 0xff, id = usage & 0xffff
        guard let base = page == 7 ? keys[id] : page == 0x0c ? consumer[id] : nil else { return nil }
        return mods.enumerated().reduce(base) { m & (1 << UInt32($1.offset)) != 0 ? "\($1.element)(\($0))" : $0 }
    }

    /// Studio binding → keymap text ("&kp ESC"). nil for a behavior this can't name, such as one not compiled into the firmware.
    static func binding(_ b: KeyBinding, behaviors: [Int: String], layers: [Int: String]) -> String? {
        func k(_ usage: UInt32) -> String { key(usage) ?? String(format: "0x%X", usage) }
        func pick(_ list: [String], _ i: UInt32) -> String { Int(i) < list.count ? list[Int(i)] : "\(i)" }
        let layer = layers[Int(b.param1)] ?? "\(b.param1)"
        switch behaviors[b.behavior] {
        case "Key Press": return "&kp \(k(b.param1))"
        case "Transparent": return "&trans"
        case "None": return "&none"
        case "Momentary Layer": return "&mo \(layer)"
        case "Toggle Layer": return "&tog \(layer)"
        case "To Layer": return "&to \(layer)"
        case "Sticky Layer": return "&sl \(b.param1)"
        case "Layer-Tap": return "&lt \(b.param1) \(k(b.param2))"
        case "Mod-Tap": return "&mt \(pick(modNames, UInt32(b.param1.trailingZeroBitCount))) \(k(b.param2))"
        case "Sticky Key": return "&sk \(k(b.param1))"
        case "Key Toggle": return "&kt \(k(b.param1))"
        case "Grave/Escape": return "&gresc"
        case "Key Repeat": return "&key_repeat"
        case "Caps Word": return "&caps_word"
        case "Bootloader": return "&bootloader"
        case "Reset": return "&sys_reset"
        case "Studio Unlock": return "&studio_unlock"
        case "External Power": return "&ext_power \(pick(["EP_OFF", "EP_ON", "EP_TOG"], b.param1))"
        case "Output Selection": return "&out \(pick(["OUT_TOG", "OUT_USB", "OUT_BLE"], b.param1))"
        case "Bluetooth": return b.param1 == 3 ? "&bt BT_SEL \(b.param2)" : "&bt \(pick(bluetooth, b.param1))"
        default: return nil
        }
    }

    static let legends: [String: String] = [
        "ESC": "Esc", "BSPC": "⌫", "TAB": "⇥", "RET": "⏎", "SPACE": "␣", "MINUS": "-", "EQUAL": "=", "LBKT": "[", "RBKT": "]",
        "BSLH": "\\", "SEMI": ";", "SQT": "'", "GRAVE": "`", "COMMA": ",", "DOT": ".", "FSLH": "/", "CAPS": "Caps",
        "PSCRN": "PrtSc", "SLCK": "ScrLk", "PAUSE_BREAK": "Pause", "INS": "Ins", "HOME": "Home", "PG_UP": "PgUp", "DEL": "Del", "END": "End", "PG_DN": "PgDn",
        "RIGHT": "→", "LEFT": "←", "DOWN": "↓", "UP": "↑", "K_CMENU": "Menu", "K_UNDO": "Undo", "K_CUT": "Cut", "K_COPY": "Copy", "K_PASTE": "Paste",
        "LCTRL": "⌃", "LSHFT": "⇧", "LALT": "⌥", "LGUI": "⌘", "RCTRL": "⌃", "RSHFT": "⇧", "RALT": "⌥", "RGUI": "⌘",
        "C_MUTE": "Mute", "C_VOL_UP": "Vol+", "C_VOL_DN": "Vol−", "C_PP": "Play", "C_NEXT": "Next", "C_PREV": "Prev",
        "LC": "⌃", "LS": "⇧", "LA": "⌥", "LG": "⌘", "RC": "⌃", "RS": "⇧", "RA": "⌥", "RG": "⌘",
    ]

    /// ZMK key name → keycap text: "N1" → "1", "LA(S)" → "⌥S", "PG_UP" → "PgUp".
    static func keyLegend(_ name: String) -> String {
        if let m = name.wholeMatch(of: #/([LR][CSAG])\((.+)\)/#) { return (legends[String(m.1)] ?? "") + keyLegend(String(m.2)) }
        if let m = name.wholeMatch(of: #/N(\d)/#) { return String(m.1) }
        return legends[name] ?? name
    }

    /// Keymap text → keycap text: "&kp ESC" → "Esc", "&mo LOWER" → "Lower", "&bt BT_SEL 0" → "BT 1", "&none" → "".
    static func legend(_ binding: String) -> String {
        let t = binding.split(separator: " ").map(String.init)
        guard let behavior = t.first else { return "" }
        let a = t.count > 1 ? t[1] : "", b = t.count > 2 ? t[2] : ""
        func layer(_ s: String) -> String { Int(s) == nil ? s.capitalized : "L\(s)" }
        func words(_ s: String, dropping prefix: String) -> String { s.replacing(prefix, with: "", maxReplacements: 1).replacing("_", with: " ").lowercased() }
        switch behavior {
        case "&kp", "&sk", "&kt": return keyLegend(a)
        case "&trans": return "▽"
        case "&none": return ""
        case "&mo", "&tog", "&to", "&sl": return layer(a)
        case "&lt": return "\(layer(a)) \(keyLegend(b))"
        case "&mt": return "\(keyLegend(a)) \(keyLegend(b))"
        case "&bt": return a == "BT_SEL" ? "BT \((Int(b) ?? 0) + 1)" : "BT \(words(a, dropping: "BT_"))"
        case "&out": return ["OUT_USB": "USB", "OUT_BLE": "BT"][a] ?? "USB/BT"
        case "&ext_power": return "Power"
        case "&rgb_ug": return "RGB \(words(a, dropping: "RGB_"))"
        case "&key_repeat": return "Rep"
        case "&caps_word": return "Caps word"
        case "&gresc": return "Esc `"
        case "&bootloader": return "Boot"
        case "&sys_reset": return "Reset"
        case "&studio_unlock": return "Unlock"
        default: return t.joined(separator: " ").replacing("&", with: "")
        }
    }
}

/// config/sofle.keymap: the fallback keymap, and the only source for the encoders (Studio doesn't expose sensor-bindings).
struct KeymapFile {
    struct Layer: Equatable { var name: String, bindings: [String], sensors: [String] }
    var layers: [Layer] = []
    /// `#define LOWER 1` → [1: "LOWER"], to print layer arguments the way the file does.
    var defines: [Int: String] = [:]

    init?(_ text: String) {
        for m in text.matches(of: #/#define[ \t]+(\w+)[ \t]+(\d+)[ \t]*\n/#) { defines[Int(m.2) ?? -1] = String(m.1) }
        func list(_ s: Substring) -> [String] {
            s.split(separator: "&").map { "&" + $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { $0 != "&" }
        }
        // Layer nodes have no nested braces, so each one is a `name { ... }` block with a `bindings` property.
        for block in text.matches(of: #/(\w+)\s*\{([^{}]*)\}/#) {
            var bindings: [String]?, sensors: [String] = []
            for p in block.2.matches(of: #/([\w-]*)bindings\s*=\s*<([^>]*)>/#) {
                if p.1.isEmpty { bindings = list(p.2) } else if p.1 == "sensor-" { sensors = list(p.2) }
            }
            guard let bindings else { continue }
            let name = block.2.firstMatch(of: #/display-name\s*=\s*"([^"]*)"/#).map { String($0.1) } ?? String(block.1)
            layers.append(Layer(name: name, bindings: bindings, sensors: sensors))
        }
        if layers.isEmpty { return nil }
    }

    /// Sensor bindings in effect on a layer: a layer without its own lets the event fall through to the layers below.
    func sensors(layer: Int) -> [String] {
        layers.prefix(layer + 1).last { !$0.sensors.isEmpty }?.sensors ?? []
    }
}
