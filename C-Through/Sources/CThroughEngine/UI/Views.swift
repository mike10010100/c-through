import AppKit
import CThroughEngine
import SwiftUI

// MARK: - Preferences

public struct DeviceAnchorData: Equatable {
    public let id: String
    public let bounds: Anchor<CGRect>
}

public struct DeviceAnchorKey: PreferenceKey {
    public static var defaultValue: [DeviceAnchorData] = []
    public static func reduce(value: inout [DeviceAnchorData], nextValue: () -> [DeviceAnchorData]) {
        value.append(contentsOf: nextValue())
    }
}

public class DeviceViewModel: ObservableObject {
    @Published public var devices: [USBDevice] = []
    private let explorer: USBExplorerProtocol

    public init(explorer: USBExplorerProtocol) {
        self.explorer = explorer
        refresh()
    }

    public func refresh() {
        devices = explorer.fetchTopology()
    }
}

// MARK: - Main View

public struct ContentView: View {
    @ObservedObject var viewModel: DeviceViewModel
    @State private var zoomScale: CGFloat = 1.0

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            // Pure SwiftUI panning and zooming
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    // Content Layer
                    HStack(alignment: .center, spacing: 100) {
                        VStack(alignment: .trailing, spacing: 40) {
                            if viewModel.devices.isEmpty {
                                Text("No USB devices found.").foregroundColor(.secondary)
                            } else {
                                ForEach(viewModel.devices) { device in
                                    DeviceTreeBranch(device: device)
                                }
                            }
                        }

                        HostMacBookNode()
                            .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                                [DeviceAnchorData(id: "HOST", bounds: $0)]
                            }
                    }
                    .padding(300) // Padding so it's pannable
                }
                .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                    // Connection Lines (Drawn strictly behind nodes)
                    GeometryReader { proxy in
                        ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                    }
                }
                .scaleEffect(zoomScale)
                // Frame ensures the scrollview content size accommodates the scaled view
                .frame(minWidth: 1500, minHeight: 1200)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = value.magnitude
                        zoomScale = max(0.2, min(newScale, 3.0))
                    }
            )

            // Overlays
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    LegendBox().padding(30)
                    Spacer()
                }
            }

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
        guard let parentAnchorData = anchors.first(where: { $0.id == parentID }) else { return }

        let p2Rect = proxy[parentAnchorData.bounds]
        let p2 = CGPoint(x: p2Rect.minX, y: p2Rect.midY) // Leading edge of parent

        for device in devices {
            if let deviceAnchorData = anchors.first(where: { $0.id == device.id }) {
                let p1Rect = proxy[deviceAnchorData.bounds]
                let p1 = CGPoint(x: p1Rect.maxX, y: p1Rect.midY) // Trailing edge of child

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
        HStack(alignment: .center, spacing: 100) {
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 20) {
                    ForEach(device.children) { child in
                        DeviceTreeBranch(device: child)
                    }
                }
            }
            DeviceCardView(device: device)
                .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                    [DeviceAnchorData(id: device.id, bounds: $0)]
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
                    .frame(width: 44, height: 44)
                Image(systemName: iconFor(device))
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                if let mfr = device.manufacturer {
                    Text(mfr).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .secondary)
                    .padding(.trailing, 12)
            }
        }
        .frame(width: 260, height: 64)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(device.isBottlenecked ? Color.red : Color.gray.opacity(0.15), lineWidth: device.isBottlenecked ? 2 : 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
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
            // Main Chassis - clean, non-glowing silver/space gray design
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.systemGray))
                .frame(width: 300, height: 210)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 15, y: 8)

            // Keyboard area well
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.darkGray))
                .frame(width: 260, height: 90)
                .offset(y: -25)

            // Trackpad
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.darkGray).opacity(0.8))
                .frame(width: 100, height: 45)
                .offset(y: 60)
            
            // Physical Port Indents on the left
            VStack(spacing: 20) {
                Capsule().fill(Color.black.opacity(0.8)).frame(width: 6, height: 16)
                Capsule().fill(Color.black.opacity(0.8)).frame(width: 6, height: 16)
            }
            .offset(x: -150, y: -20)
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
