import AppKit
import CThroughEngine
import SwiftUI

// MARK: - Preferences

struct DeviceAnchorData: Equatable {
    let id: String
    let leading: Anchor<CGPoint>?
    let trailing: Anchor<CGPoint>?

    /// Helper to merge anchors for the same ID
    static func merge(id: String, leading: Anchor<CGPoint>? = nil, trailing: Anchor<CGPoint>? = nil, in list: inout [DeviceAnchorData]) {
        if let index = list.firstIndex(where: { $0.id == id }) {
            let existing = list[index]
            list[index] = DeviceAnchorData(
                id: id,
                leading: leading ?? existing.leading,
                trailing: trailing ?? existing.trailing
            )
        } else {
            list.append(DeviceAnchorData(id: id, leading: leading, trailing: trailing))
        }
    }
}

struct DeviceAnchorKey: PreferenceKey {
    static var defaultValue: [DeviceAnchorData] = []
    static func reduce(value: inout [DeviceAnchorData], nextValue: () -> [DeviceAnchorData]) {
        for next in nextValue() {
            DeviceAnchorData.merge(id: next.id, leading: next.leading, trailing: next.trailing, in: &value)
        }
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

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            // Native macOS Zoomable/Pannable ScrollView
            NSZoomableScrollView {
                ZStack {
                    // Content Layer
                    HStack(alignment: .center, spacing: 200) {
                        VStack(alignment: .trailing, spacing: 80) {
                            if viewModel.devices.isEmpty {
                                Text("No USB devices found.").foregroundColor(.secondary)
                            } else {
                                ForEach(viewModel.devices) { device in
                                    DeviceTreeBranch(device: device)
                                }
                            }
                        }

                        HostMacBookNode()
                            .anchorPreference(key: DeviceAnchorKey.self, value: .leading) {
                                [DeviceAnchorData(id: "HOST", leading: $0, trailing: nil)]
                            }
                    }
                    .padding(600) // Huge padding for panning room
                }
                .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                    // Connection Lines (Drawn behind nodes)
                    GeometryReader { proxy in
                        ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                    }
                }
            }

            // Legend Overlay
            VStack {
                Spacer()
                HStack {
                    LegendBox().padding(40)
                    Spacer()
                }
            }

            // Controls Overlay
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

// MARK: - Native Zoomable ScrollView

struct NSZoomableScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 10.0
        scrollView.minMagnification = 0.1
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Match the container size
        hostingView.frame = NSRect(x: 0, y: 0, width: 5000, height: 5000)
        scrollView.documentView = hostingView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
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
        guard let parentAnchorData = anchors.first(where: { $0.id == parentID }),
              let p2Anchor = parentAnchorData.leading else { return }

        let p2 = proxy[p2Anchor]

        for device in devices {
            if let deviceAnchorData = anchors.first(where: { $0.id == device.id }),
               let p1Anchor = deviceAnchorData.trailing {
                let p1 = proxy[p1Anchor]

                var path = Path()
                path.move(to: p1)

                // Smooth organic curve
                let diff = p2.x - p1.x
                let control1 = CGPoint(x: p1.x + diff * 0.4, y: p1.y)
                let control2 = CGPoint(x: p1.x + diff * 0.6, y: p2.y)
                path.addCurve(to: p2, control1: control1, control2: control2)

                let color = device.isBottlenecked ? Color.red : Color.gray.opacity(0.4)
                let thickness = lineThickness(for: device.negotiatedSpeedMbps)

                context.stroke(path, with: .color(color), lineWidth: thickness)

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
        HStack(alignment: .center, spacing: 150) {
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 40) {
                    ForEach(device.children) { child in
                        DeviceTreeBranch(device: child)
                    }
                }
            }
            DeviceCardView(device: device)
                .anchorPreference(key: DeviceAnchorKey.self, value: .trailing) {
                    [DeviceAnchorData(id: device.id, leading: nil, trailing: $0)]
                }
                .anchorPreference(key: DeviceAnchorKey.self, value: .leading) {
                    [DeviceAnchorData(id: device.id, leading: $0, trailing: nil)]
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
            Spacer(minLength: 40)
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
            // Chassis
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.25)], startPoint: .top, endPoint: .bottom))
                .frame(width: 380, height: 260)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 15)

            // Unified screen and keyboard well to match mockup style
            VStack(spacing: 15) {
                // Screen Area
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 340, height: 140)
                    .overlay(
                        Circle().fill(Color.blue.opacity(0.1)).blur(radius: 30).frame(width: 150)
                    )

                // Keyboard area well
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 300, height: 45)

                // Trackpad
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 120, height: 35)
            }
            .offset(y: -10)

            // Ports
            VStack(spacing: 30) {
                Capsule().fill(Color.black).frame(width: 5, height: 18)
                Capsule().fill(Color.black).frame(width: 5, height: 18)
            }
            .offset(x: -188, y: -20)
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
