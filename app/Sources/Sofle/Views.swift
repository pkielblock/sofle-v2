import SceneKit
import SwiftUI

struct SofleApp: App {
    @StateObject private var keyboard = Keyboard()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel().environmentObject(keyboard)
        } label: {
            Image(systemName: "keyboard")
            if keyboard.connected {
                Text([Keyboard.Half.left, .right].map { percent($0 == .right && !keyboard.rightConnected ? nil : keyboard.levels[$0]) }.joined(separator: " · "))
            }
        }
        .menuBarExtraStyle(.window)

        Window("Sofle", id: "keyboard") {
            KeyboardWindow().environmentObject(keyboard)
        }
        .defaultSize(width: 1120, height: 640)
        // --window: open the keyboard at launch instead of waiting for the menu.
        .defaultLaunchBehavior(CommandLine.arguments.contains("--window") ? .presented : .suppressed)
    }
}

private func percent(_ level: Int?) -> String {
    level.map { (Double($0) / 100).formatted(.percent) } ?? "–"
}

// MARK: - Menu bar panel

struct MenuPanel: View {
    @EnvironmentObject private var keyboard: Keyboard
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Kiel.Space.s4) {
            HStack {
                Text(verbatim: Keyboard.name).font(Kiel.Font.title).foregroundStyle(Kiel.text)
                Spacer()
                status
            }
            if keyboard.bluetooth == .unauthorized {
                Text("Allow Bluetooth for Sofle in System Settings › Privacy & Security › Bluetooth")
                    .font(Kiel.Font.footnote).foregroundStyle(Kiel.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The estimate moves with the clock, not only with new readings.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: Kiel.Space.s2) {
                    half(.left, "Left", now: context.date)
                    half(.right, "Right", now: context.date)
                }
            }
            HStack {
                Button("Show keyboard") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "keyboard")
                }
                .buttonStyle(KielButtonStyle(kind: .primary, size: .small))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(KielButtonStyle(kind: .ghost, size: .small))
            }
        }
        .padding(Kiel.Space.s4)
        .frame(width: 320)
        .background(Kiel.bg)
    }

    @ViewBuilder private var status: some View {
        switch keyboard.bluetooth {
        case .unauthorized: KielBadge(text: String(localized: "Bluetooth permission needed"), tone: .neg)
        case .poweredOff: KielBadge(text: String(localized: "Bluetooth is off"), tone: .warn)
        default:
            keyboard.connected
                ? KielBadge(text: String(localized: "Connected"), tone: .pos)
                : KielBadge(text: String(localized: "Not connected"))
        }
    }

    private func half(_ half: Keyboard.Half, _ title: LocalizedStringKey, now: Date) -> some View {
        let answering = keyboard.connected && (half == .left || keyboard.rightConnected)
        let level = answering ? keyboard.levels[half] : nil
        let note: String? = !keyboard.connected ? nil
            : !answering ? String(localized: "Off or out of range")
            : timeLeftText(keyboard.timeLeft(half, now: now))
        return VStack(alignment: .leading, spacing: Kiel.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Kiel.Font.footnote).foregroundStyle(Kiel.text2)
                Spacer()
                if let note { Text(note).font(Kiel.Font.caption).foregroundStyle(Kiel.text3) }
            }
            Text(percent(level)).font(Kiel.Font.money(28)).foregroundStyle(level == nil ? Kiel.text3 : Kiel.text)
                .contentTransition(.numericText())
            // KielMeter's own colors read "fuller is worse"; a battery is the other way round.
            KielMeter(value: Double(level ?? 0) / 100, neutralColor: (level ?? 100) <= 10 ? Kiel.neg : (level ?? 100) <= 25 ? Kiel.warn : Kiel.pos)
        }
        .kielCard(padding: Kiel.Space.s4, radius: Kiel.Radius.lg)
        .accessibilityElement(children: .combine)
    }

    private func timeLeftText(_ timeLeft: TimeLeft) -> String? {
        switch timeLeft {
        case .estimating: return String(localized: "Estimating…")
        case .charging: return nil
        case .left(let seconds):
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = [.day, .hour, .minute]
            formatter.maximumUnitCount = 1
            formatter.includesApproximationPhrase = true
            formatter.includesTimeRemainingPhrase = true
            return formatter.string(from: seconds)
        }
    }
}

// MARK: - Keyboard window

struct KeyboardWindow: View {
    @EnvironmentObject private var keyboard: Keyboard
    @State private var picked = 0

    var body: some View {
        let layer = min(picked, max(keyboard.layers.count - 1, 0))
        let bindings = keyboard.layers.indices.contains(layer) ? keyboard.layers[layer].bindings : []
        let encoders = [0, 1].map { encoder($0, layer: layer, bindings: bindings) }
        VStack(spacing: 0) {
            BoardView(
                keys: keyboard.keys,
                legends: bindings.map(Labels.legend),
                knobs: encoders.map { "↻ \($0.right)\n\($0.press)\n↺ \($0.left)" },
                screens: [
                    Screens.left(output: keyboard.output, linked: keyboard.connected, level: keyboard.levels[.left],
                                 layer: keyboard.layers.indices.contains(layer) ? keyboard.layers[layer].name : ""),
                    keyboard.connected ? Screens.right(level: keyboard.rightConnected ? keyboard.levels[.right] : nil) : Screens.off,
                ]
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Keyboard, layer \(name(layer))"))
            .accessibilityValue(bindings.map(Labels.legend).filter { !$0.isEmpty }.joined(separator: ", "))

            VStack(alignment: .leading, spacing: Kiel.Space.s3) {
                HStack(spacing: Kiel.Space.s6) {
                    source
                    Spacer()
                    knob("Left encoder", encoders[0])
                    knob("Right encoder", encoders[1])
                }
                Text(keyboard.source == .snapshot
                     ? "The keyboard didn't answer, so this is config/sofle.keymap from the repository. It may differ from what's on the keyboard."
                     : "The screens show the live battery and connection. The layer is the one picked here and the Bluetooth profile number is left out, because the keyboard doesn't report them.")
                    .font(Kiel.Font.caption).foregroundStyle(Kiel.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Kiel.Space.s6)
            .padding(.vertical, Kiel.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Kiel.surface)
            .overlay(alignment: .top) { Kiel.line.frame(height: 1) }
        }
        .background(Kiel.bg)
        .containerBackground(Kiel.bg, for: .window)
        .frame(minWidth: 880, minHeight: 480)
        .toolbarBackground(Kiel.bg, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layer", selection: $picked) {
                    ForEach(keyboard.layers.indices, id: \.self) { Text(name($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Read again", systemImage: "arrow.clockwise") { keyboard.readKeymap() }
                    .help("Read again")
            }
        }
    }

    @ViewBuilder private var source: some View {
        switch keyboard.source {
        case .live: KielBadge(text: String(localized: "Read from the keyboard"), tone: .pos)
        case .snapshot: KielBadge(text: String(localized: "Snapshot from the repository"), tone: .warn)
        case .loading: KielBadge(text: String(localized: "Reading keymap…"))
        }
    }

    /// The keyboard's own layer names, shown as they are.
    private func name(_ layer: Int) -> String {
        let name = keyboard.layers.indices.contains(layer) ? keyboard.layers[layer].name : ""
        return name.isEmpty ? String(localized: "Layer \(layer + 1)") : name.capitalized
    }

    /// Turning comes from the file's sensor-bindings (`&inc_dec_kp <clockwise> <counterclockwise>`), pressing from the keymap.
    private func encoder(_ half: Int, layer: Int, bindings: [String]) -> (right: String, left: String, press: String) {
        let sensors = keyboard.file?.sensors(layer: layer) ?? []
        let turn = sensors.indices.contains(half) ? sensors[half].split(separator: " ").dropFirst().map { Labels.keyLegend(String($0)) } : []
        let position = Layout.encoders[half]
        return (turn.first ?? "?", turn.count > 1 ? turn[1] : "?", bindings.indices.contains(position) ? Labels.legend(bindings[position]) : "")
    }

    private func knob(_ title: LocalizedStringKey, _ encoder: (right: String, left: String, press: String)) -> some View {
        HStack(spacing: Kiel.Space.s3) {
            Text(title).foregroundStyle(Kiel.text2)
            Label(encoder.right, systemImage: "arrow.clockwise").accessibilityLabel(Text("Turn right: \(encoder.right)"))
            Label(encoder.left, systemImage: "arrow.counterclockwise").accessibilityLabel(Text("Turn left: \(encoder.left)"))
            Label(encoder.press, systemImage: "arrow.down.to.line").accessibilityLabel(Text("Press: \(encoder.press)"))
        }
        .font(Kiel.Font.footnote)
        .foregroundStyle(Kiel.text)
        .labelStyle(.titleAndIcon)
    }
}

struct BoardView: NSViewRepresentable {
    let keys: [KeyPosition], legends: [String], knobs: [String], screens: [CGImage]

    func makeCoordinator() -> Board { Board() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.show(keys: keys, legends: legends, knobs: knobs, screens: screens)
    }
}
