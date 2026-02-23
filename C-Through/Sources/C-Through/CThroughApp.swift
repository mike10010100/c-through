import CThroughEngine
import SwiftUI

// MARK: - Preferences

struct DeviceAnchorData: Equatable {
    let id: String
    let center: Anchor<CGPoint>
}

struct DeviceAnchorKey: PreferenceKey {
    static var defaultValue: [DeviceAnchorData] = []
    static func reduce(value: inout [DeviceAnchorData], nextValue: () -> [DeviceAnchorData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - App Entry

@main
struct CThroughApp: App {
    @StateObject private var viewModel = DeviceViewModel(explorer: USBExplorer())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1200, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class DeviceViewModel: ObservableObject {
    @Published var devices: [USBDevice] = []
    private let explorer: USBExplorerProtocol

    init(explorer: USBExplorerProtocol) {
        self.explorer = explorer
        refresh()
    }

    func refresh() {
        devices = explorer.fetchTopology()
    }
}

// MARK: - Main View

struct ContentView: View {
    @ObservedObject var viewModel: DeviceViewModel
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            // The Scrollable/Zoomable Canvas
            GeometryReader { proxy in
                ZStack {
                    // Tree Content
                    HStack(alignment: .center, spacing: 150) {
                        // Devices
                        VStack(alignment: .trailing, spacing: 60) {
                            if viewModel.devices.isEmpty {
                                Text("No USB devices found.").foregroundColor(.secondary)
                            } else {
                                ForEach(viewModel.devices) { device in
                                    DeviceTreeBranch(device: device)
                                }
                            }
                        }

                        // Host
                        HostMacBookNode()
                            .anchorPreference(key: DeviceAnchorKey.self, value: .center) {
                                [DeviceAnchorData(id: "HOST", center: $0)]
                            }
                    }
                    .padding(200)
                    .scaleEffect(zoomScale)
                    .offset(offset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Draw Connection Lines on top using preferences
                .overlayPreferenceValue(DeviceAnchorKey.self) { anchors in
                    ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in zoomScale = value.magnitude }
            )

            // Overlays
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    LegendBox().padding(40)
                    Spacer()
                    // Zoom readout
                    if zoomScale != 1.0 {
                        Text("\(Int(zoomScale * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(8)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .padding(40)
                    }
                }
            }

            // Refresh Button
            VStack {
                HStack {
                    Spacer()
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .padding(30)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Connections

struct ConnectionLinesView: View {
    let anchors: [DeviceAnchorData]
    let devices: [USBDevice]
    let proxy: GeometryProxy

    var body: some View {
        Canvas { context, _ in
            drawLines(for: devices, to: "HOST", in: &context)
        }
        .allowsHitTesting(false)
    }

    private func drawLines(for devices: [USBDevice], to parentID: String, in context: inout GraphicsContext) {
        guard let parentAnchor = anchors.first(where: { $0.id == parentID }) else { return }
        let p2 = proxy[parentAnchor.center]

        for device in devices {
            if let deviceAnchor = anchors.first(where: { $0.id == device.id }) {
                let p1 = proxy[deviceAnchor.center]

                var path = Path()
                path.move(to: p1)

                // Beautiful cubic bezier for the "cable"
                let control1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                let control2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                path.addCurve(to: p2, control1: control1, control2: control2)

                let color = device.isBottlenecked ? Color.red : Color.gray.opacity(0.4)
                let thickness = lineThickness(for: device.negotiatedSpeedMbps)

                context.stroke(path, with: .color(color), lineWidth: thickness)

                // Recurse for children
                drawLines(for: device.children, to: device.id, in: &context)
            }
        }
    }

    private func lineThickness(for speed: Double?) -> CGFloat {
        let s = speed ?? 480.0
        if s <= 12.0 { return 1.5 }
        if s <= 480.0 { return 3.0 }
        if s <= 5000.0 { return 5.0 }
        if s <= 10000.0 { return 7.0 }
        return 10.0
    }
}

// MARK: - Nodes

struct DeviceTreeBranch: View {
    let device: USBDevice
    var body: some View {
        HStack(alignment: .center, spacing: 100) {
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 30) {
                    ForEach(device.children) { child in
                        DeviceTreeBranch(device: child)
                    }
                }
            }
            DeviceCardView(device: device)
                .anchorPreference(key: DeviceAnchorKey.self, value: .center) {
                    [DeviceAnchorData(id: device.id, center: $0)]
                }
        }
    }
}

struct DeviceCardView: View {
    let device: USBDevice
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue)
                    .frame(width: 48, height: 48)
                Image(systemName: iconFor(device))
                    .font(.system(size: 22))
                    .foregroundColor(.white)
            }
            .padding(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                if let mfr = device.manufacturer {
                    Text(mfr).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 30)
            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .secondary)
                    .padding(.trailing, 15)
            }
        }
        .frame(width: 280, height: 70)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(device.isBottlenecked ? Color.red : Color.white.opacity(0.1), lineWidth: device.isBottlenecked ? 2 : 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private func iconFor(_ device: USBDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("hub") { return "cable.connector" }
        if name.contains("ssd") || name.contains("drive") { return "externaldrive.fill" }
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse") || name.contains("trackpad") || name.contains("receiver") { return "mouse.fill" }
        if name.contains("display") { return "desktopcomputer" }
        if name.contains("camera") || name.contains("brio") { return "camera.fill" }
        if name.contains("mic") || name.contains("yeti") { return "mic.fill" }
        return "usb.fill"
    }
}

struct HostMacBookNode: View {
    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 360, height: 260)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            // Screen
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .frame(width: 320, height: 150)
                .offset(y: -30)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        .offset(y: -30)
                )
                .overlay(
                    Circle().fill(Color.blue.opacity(0.1)).blur(radius: 30).frame(width: 150).offset(y: -30)
                )

            // Keyboard area
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.4))
                .frame(width: 280, height: 50)
                .offset(y: 75)

            // Trackpad
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.03))
                .frame(width: 110, height: 40)
                .offset(y: 105)

            // Ports
            VStack(spacing: 30) {
                Capsule().fill(Color.black).frame(width: 5, height: 18)
                Capsule().fill(Color.black).frame(width: 5, height: 18)
            }
            .offset(x: -178, y: -20)
        }
    }
}

struct LegendBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LegendRow(speed: "1.5 Mbps", label: "USB 1.0", weight: 1.5)
            LegendRow(speed: "480 Mbps", label: "USB 2.0", weight: 3.0)
            LegendRow(speed: "5,000 Mbps", label: "USB 3.0", weight: 5.0)
            LegendRow(speed: "10,000 Mbps", label: "USB 3.1", weight: 7.0)
            LegendRow(speed: "40,000 Mbps", label: "Thunderbolt 3", weight: 10.0)
            Divider().padding(.vertical, 4)
            HStack {
                Capsule().fill(Color.red).frame(width: 40, height: 4)
                Text("Limited by cable throughput").font(.caption2).foregroundColor(.red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
}

struct LegendRow: View {
    let speed: String; let label: String; let weight: CGFloat
    var body: some View {
        HStack {
            Capsule().fill(Color.gray.opacity(0.5)).frame(width: 40, height: weight)
            Text(speed).font(.system(size: 10, design: .monospaced))
            Spacer()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(width: 180)
    }
}
