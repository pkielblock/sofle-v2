import XCTest
@testable import Sofle

final class SofleTests: XCTestCase {
    func testFraming() {
        let payload: [UInt8] = [0x01, 0xAB, 0xAC, 0xAD, 0x02]
        let frame = Framing.encode(payload)
        XCTAssertEqual(frame, [0xAB, 0x01, 0xAC, 0xAB, 0xAC, 0xAC, 0xAC, 0xAD, 0x02, 0xAD])

        // Noise before the frame, then two frames back to back, fed a byte at a time as Bluetooth delivers them.
        var decoder = Framing.Decoder()
        let decoded = ([0x00, 0xAD] + frame + Framing.encode([0x07])).compactMap { decoder.feed($0) }
        XCTAssertEqual(decoded, [payload, [0x07]])
    }

    func testRequestsOnlyRead() {
        // request_id 1, keymap { get_keymap: true } / { get_physical_layouts: true }, behaviors { get_behavior_details { behavior_id: 3 } }
        XCTAssertEqual(StudioRequest.keymap.encode(id: 1), [0x08, 0x01, 0x2A, 0x02, 0x08, 0x01])
        XCTAssertEqual(StudioRequest.physicalLayouts.encode(id: 2), [0x08, 0x02, 0x2A, 0x02, 0x30, 0x01])
        XCTAssertEqual(StudioRequest.behaviorDetails(3).encode(id: 300), [0x08, 0xAC, 0x02, 0x22, 0x04, 0x12, 0x02, 0x08, 0x03])
    }

    func testResponses() {
        // Response { request_response { request_id: 5, keymap { get_keymap { layers { id: 0, name: "default", bindings { behavior_id: 3, param1: 0x70029 } } } } } }
        let binding = PB.field(1, 6) + PB.field(2, 0x70029)  // sint32 3 is zigzag 6
        let layer = PB.field(2, Array("default".utf8)) + PB.field(3, binding)
        let response = PB.field(1, PB.field(1, 5) + PB.field(5, PB.field(1, PB.field(1, layer))))
        guard case let (5, .keymap(layers))? = StudioResponse.decode(response) else { return XCTFail("not a keymap") }
        XCTAssertEqual(layers.first?.name, "default")
        XCTAssertEqual(layers.first?.bindings, [KeyBinding(behavior: 3, param1: 0x70029, param2: 0)])

        // A key 1u wide at x 4.9, turned 12 degrees; negative values are zigzag too (-2400 → 4799).
        let key = PB.field(1, 200) + PB.field(2, 200) + PB.field(3, 980) + PB.field(5, 2400) + PB.field(6, 4799)
        let layouts = PB.field(1, PB.field(1, 6) + PB.field(5, PB.field(6, PB.field(2, PB.field(2, key)))))
        guard case let (6, .physicalLayout(keys))? = StudioResponse.decode(layouts) else { return XCTFail("not a layout") }
        XCTAssertEqual(keys, [KeyPosition(x: 4.9, y: 0, w: 1, h: 1, r: 12, rx: -24, ry: 0)])

        // meta { simple_error } is an error; truncated bytes and notifications don't crash and aren't answers.
        guard case (7, .error)? = StudioResponse.decode(PB.field(1, PB.field(1, 7) + PB.field(2, PB.field(2, 1)))) else { return XCTFail("not an error") }
        XCTAssertNil(StudioResponse.decode(Array(response.dropLast(9))))
        XCTAssertNil(StudioResponse.decode(PB.field(2, [0x08, 0x01])))
    }

    func testLabels() {
        XCTAssertEqual(Labels.key(0x0007_0029), "ESC")
        XCTAssertEqual(Labels.key(0x0407_0016), "LA(S)")
        XCTAssertEqual(Labels.key(0x0807_002C), "LG(SPACE)")
        XCTAssertEqual(Labels.key(0x000C_00E2), "C_MUTE")
        XCTAssertNil(Labels.key(0x0007_00FF))

        let behaviors = [3: "Key Press", 7: "Momentary Layer", 17: "Bluetooth", 21: "Transparent"], layers = [1: "LOWER"]
        func text(_ behavior: Int, _ p1: UInt32 = 0, _ p2: UInt32 = 0) -> String? {
            Labels.binding(KeyBinding(behavior: behavior, param1: p1, param2: p2), behaviors: behaviors, layers: layers)
        }
        XCTAssertEqual(text(3, 0x0007_001E), "&kp N1")
        XCTAssertEqual(text(7, 1), "&mo LOWER")
        XCTAssertEqual(text(17, 3, 2), "&bt BT_SEL 2")
        XCTAssertEqual(text(17, 0), "&bt BT_CLR")
        XCTAssertEqual(text(21), "&trans")
        XCTAssertNil(text(0xffff, 4))

        let legends = ["&kp N1": "1", "&kp LA(S)": "⌥S", "&kp PG_UP": "PgUp", "&kp C_MUTE": "Mute", "&mo LOWER": "Lower", "&bt BT_SEL 2": "BT 3",
                       "&bt BT_CLR": "BT clr", "&rgb_ug RGB_TOG": "RGB tog", "&trans": "▽", "&none": "", "&key_repeat": "Rep", "&kp Q": "Q"]
        for (binding, legend) in legends { XCTAssertEqual(Labels.legend(binding), legend, binding) }
    }

    func testKeymapFile() throws {
        let path = URL(fileURLWithPath: #filePath).appendingPathComponent("../../../../config/sofle.keymap").standardized
        let file = try XCTUnwrap(KeymapFile(try String(contentsOf: path, encoding: .utf8)))
        XCTAssertEqual(file.layers.map(\.name), ["default", "lower", "raise", "adjust"])
        XCTAssertEqual(file.layers.map(\.bindings.count), [60, 60, 60, 60])
        XCTAssertEqual(file.defines, [0: "BASE", 1: "LOWER", 2: "RAISE", 3: "ADJUST"])
        XCTAssertEqual(file.layers[0].bindings[0], "&kp ESC")
        XCTAssertEqual(file.layers[2].bindings[1], "&bt BT_SEL 0")
        XCTAssertEqual(file.layers[0].sensors, ["&inc_dec_kp C_VOL_UP C_VOL_DN", "&inc_dec_kp PG_UP PG_DN"])
        // The adjust layer has no sensor-bindings of its own.
        XCTAssertEqual(file.sensors(layer: 3), file.layers[2].sensors)
        XCTAssertNil(KeymapFile("/ { };"))
    }

    func testTimeLeft() {
        let start = Date(timeIntervalSince1970: 0)
        func readings(_ levels: [(minutes: Double, level: Int)]) -> [Reading] { levels.map { Reading(t: start + $0.minutes * 60, level: $0.level) } }
        let now = start + 10 * 3600

        XCTAssertEqual(TimeLeft.estimate([], now: now), .estimating)
        XCTAssertEqual(TimeLeft.estimate(readings([(0, 80)]), now: now), .estimating)                      // no drop yet
        XCTAssertEqual(TimeLeft.estimate(readings([(0, 80), (10, 70)]), now: start + 20 * 60), .estimating) // under half an hour
        XCTAssertEqual(TimeLeft.estimate(readings([(0, 50), (60, 55)]), now: now), .charging)
        // 20 points in 10 hours with 60 left: 30 hours.
        XCTAssertEqual(TimeLeft.estimate(readings([(0, 80), (300, 70), (590, 60)]), now: now), .left(30 * 3600))
        // Charged to 90, then down to 80 in 5 hours: the run starts at the peak, 40 hours left.
        XCTAssertEqual(TimeLeft.estimate(readings([(0, 40), (200, 90), (400, 80)]), now: start + 500 * 60), .left(40 * 3600))
    }
}
