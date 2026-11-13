import CoreBluetooth
import Foundation
import IOKit

/// The keyboard: both battery levels (Bluetooth Battery Service) and the keymap (ZMK Studio RPC, read-only).
final class Keyboard: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Source { case loading, live, snapshot }
    enum Half: String { case left, right }
    /// ZMK answers Studio only on the output it's typing on, so the transport that answers is the keyboard's output.
    enum Transport { case usb, bluetooth }

    static let name = "Sofle"
    static let keymapURL = URL(string: "https://raw.githubusercontent.com/pkielblock/sofle-v2/main/config/sofle.keymap")!
    private static let battery = CBUUID(string: "180F"), level = CBUUID(string: "2A19"), description = CBUUID(string: "2901")
    // zmk app/src/studio/uuid.h
    private static let studio = CBUUID(string: "00000000-0196-6107-C967-C5CFB1C2482A")
    private static let rpcUUID = CBUUID(string: "00000001-0196-6107-C967-C5CFB1C2482A")

    @Published private(set) var bluetooth = CBManagerState.unknown
    @Published private(set) var connected = false
    @Published private(set) var levels: [Half: Int] = [:]
    @Published private(set) var history: [String: [Reading]] = [:]
    @Published private(set) var source = Source.loading
    @Published private(set) var output: Transport?
    @Published private(set) var layers: [(name: String, bindings: [String])] = []
    @Published private(set) var keys = Layout.sofle
    @Published private(set) var file: KeymapFile?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rpc: CBCharacteristic?
    private var serial: (fd: Int32, source: DispatchSourceRead)?
    private var transports: [Transport] = []  // still to try; the first one is in use
    private var decoder = Framing.Decoder()
    private var queue: [StudioRequest] = []
    private var requestID: UInt64 = 0
    private var timeout: DispatchWorkItem?
    private var studioFailed = false
    private var reading: [(name: String, bindings: [KeyBinding])] = []
    private var behaviors: [Int: String] = [:]
    private var live: (layers: [(name: String, bindings: [KeyBinding])], behaviors: [Int: String])?

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "history"), let saved = try? JSONDecoder().decode([String: [Reading]].self, from: data) {
            history = saved
        }
        central = CBCentralManager(delegate: self, queue: nil)
        // macOS doesn't tell an app when an already-paired keyboard reconnects, so look for it.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.find() }
        readKeymap()
        Task { @MainActor in
            let request = URLRequest(url: Self.keymapURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let fetched = (try? await URLSession.shared.data(for: request)).flatMap { data, response in
                (response as? HTTPURLResponse)?.statusCode == 200 ? KeymapFile(String(decoding: data, as: UTF8.self)) : nil
            }
            // Offline: the copy of the file that build.sh put in the app.
            file = fetched ?? Bundle.main.url(forResource: "sofle", withExtension: "keymap")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }.flatMap(KeymapFile.init)
            rebuild()
        }
    }

    /// The right half reports 0 through the left one while it's off or out of range.
    var rightConnected: Bool { (levels[.right] ?? 0) > 0 }
    func timeLeft(_ half: Half, now: Date = .now) -> TimeLeft { .estimate(history[half.rawValue] ?? [], now: now) }

    // MARK: Bluetooth

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetooth = central.state
        find()
    }

    private func find() {
        guard central.state == .poweredOn, peripheral == nil else { return }
        // Other keyboards have a Battery Service too, so match the name.
        guard let p = central.retrieveConnectedPeripherals(withServices: [Self.battery]).first(where: { $0.name == Self.name }) else { return }
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        connected = true
        p.discoverServices([Self.battery, Self.studio])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { dropped() }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { dropped() }

    private func dropped() {
        peripheral = nil; rpc = nil; connected = false; levels = [:]
        if transports.first == .bluetooth { nextTransport() } else { transports.removeAll { $0 == .bluetooth } }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(s.uuid == Self.battery ? [Self.level] : [Self.rpcUUID], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.level {
                p.discoverDescriptors(for: c)  // the description tells the halves apart, so read values after it
            } else if c.uuid == Self.rpcUUID {
                p.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor c: CBCharacteristic, error: Error?) {
        p.readValue(for: c)
        p.setNotifyValue(true, for: c)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.rpcUUID, error == nil else { return }
        rpc = c
        if queue.isEmpty { readKeymap() } else if !transports.contains(.bluetooth) { transports.append(.bluetooth) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        if c.uuid == Self.level, let value = data.first {
            // ZMK's second Battery Level, the one with a "Peripheral 0" description, is the right half.
            let half: Half = c.descriptors?.contains { $0.uuid == Self.description } == true ? .right : .left
            levels[half] = Int(value)
            record(half, Int(value))
        } else if c.uuid == Self.rpcUUID, transports.first == .bluetooth {
            received(data)
        }
    }

    private func record(_ half: Half, _ level: Int) {
        var readings = history[half.rawValue] ?? []
        guard level > 0, readings.last?.level != level else { return }  // 0 is "no reading", not a level
        readings.append(Reading(t: .now, level: level))
        history[half.rawValue] = readings.suffix(200)
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "history")
    }

    // MARK: USB serial

    /// The serial port of the USB device named like the keyboard, so nothing is ever written to another device.
    private static func serialPath() -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOSerialBSDClient"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            let product = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "USB Product Name" as CFString, nil, options) as? String
            let path = IORegistryEntryCreateCFProperty(service, "IOCalloutDevice" as CFString, nil, 0)?.takeRetainedValue() as? String
            if product == name, let path { return path }
        }
        return nil
    }

    private func openSerial() -> Bool {
        closeSerial()
        guard let path = Self.serialPath() else { return false }
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        var settings = termios()
        tcgetattr(fd, &settings); cfmakeraw(&settings); cfsetspeed(&settings, speed_t(B115200)); tcsetattr(fd, TCSANOW, &settings)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { self?.received(Data(buffer.prefix(n))) } else if n == 0 || errno != EAGAIN { self?.closeSerial() }  // unplugged
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        serial = (fd, source)
        return true
    }

    private func closeSerial() {
        serial?.source.cancel()
        serial = nil
    }

    // MARK: ZMK Studio

    /// Reads the keymap again, over USB when the keyboard is plugged in and over Bluetooth otherwise.
    /// Only get requests exist (see StudioRequest).
    func readKeymap() {
        transports = (openSerial() ? [.usb] : []) + (rpc != nil ? [.bluetooth] : [])
        attempt()
    }

    private func attempt() {
        timeout?.cancel()
        decoder = Framing.Decoder(); reading = []; behaviors = [:]
        queue = transports.isEmpty ? [] : [.keymap]
        studioFailed = transports.isEmpty
        if transports.first != .usb { closeSerial() }
        rebuild()
        sendNext()
    }

    private func nextTransport() {
        if !transports.isEmpty { transports.removeFirst() }
        attempt()
    }

    private func sendNext() {
        guard let transport = transports.first, let request = queue.first else { return }
        requestID += 1
        let bytes = Framing.encode(request.encode(id: requestID))
        if transport == .usb, let serial {
            _ = bytes.withUnsafeBytes { write(serial.fd, $0.baseAddress, $0.count) }
        } else if let peripheral, let rpc {
            let size = peripheral.maximumWriteValueLength(for: .withResponse)
            for start in stride(from: 0, to: bytes.count, by: size) {
                peripheral.writeValue(Data(bytes[start..<min(start + size, bytes.count)]), for: rpc, type: .withResponse)
            }
        }
        armTimeout()
    }

    /// Bluetooth replies come as many small indications, so this is time without any, not time for a whole reply.
    private func armTimeout() {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.nextTransport() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func received(_ data: Data) {
        guard !queue.isEmpty else { return }
        armTimeout()
        for byte in data { if let payload = decoder.feed(byte) { handle(payload) } }
    }

    private func handle(_ payload: [UInt8]) {
        guard let (id, response) = StudioResponse.decode(payload), id == requestID, !queue.isEmpty else { return }
        queue.removeFirst()
        switch response {
        case .keymap(let layers):
            reading = layers
            // 0xffff: a behavior that isn't in this firmware (RGB keys with RGB off).
            let ids = Set(layers.flatMap { $0.bindings.map(\.behavior) }).subtracting([0xffff]).sorted()
            queue += ids.map { .behaviorDetails($0) } + [.physicalLayouts]
        case .behavior(let id, let name): behaviors[id] = name
        case .physicalLayout(let layout): if !layout.isEmpty { keys = layout }
        case .error: return nextTransport()
        }
        guard queue.isEmpty else { return sendNext() }
        timeout?.cancel()
        live = (reading, behaviors)
        output = transports.first
        transports = []
        closeSerial()
        rebuild()
    }

    private func rebuild() {
        if let live {
            layers = live.layers.enumerated().map { li, layer in
                (layer.name, layer.bindings.enumerated().map { i, b in
                    let original = file.flatMap { $0.layers.indices.contains(li) && $0.layers[li].bindings.indices.contains(i) ? $0.layers[li].bindings[i] : nil }
                    return Labels.binding(b, behaviors: live.behaviors, layers: file?.defines ?? [:]) ?? original ?? "?"
                })
            }
            source = .live
        } else if let file, studioFailed {
            layers = file.layers.map { ($0.name, $0.bindings) }
            source = .snapshot
        } else {
            source = .loading
        }
    }
}
