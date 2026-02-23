import AppKit
import CThroughEngine
import SwiftUI

// MARK: - Preferences

public struct DeviceAnchorData: Equatable {
    public let id: String
    public var leading: Anchor<CGPoint>?
    public var trailing: Anchor<CGPoint>?

    public init(id: String, leading: Anchor<CGPoint>? = nil, trailing: Anchor<CGPoint>? = nil) {
        self.id = id
        self.leading = leading
        self.trailing = trailing
    }
}

public struct DeviceAnchorKey: PreferenceKey {
    public static var defaultValue: [DeviceAnchorData] = []
    public static func reduce(value: inout [DeviceAnchorData], nextValue: () -> [DeviceAnchorData]) {
        for next in nextValue() {
            if let index = value.firstIndex(where: { $0.id == next.id }) {
                if let l = next.leading { value[index].leading = l }
                if let t = next.trailing { value[index].trailing = t }
            } else {
                value.append(next)
            }
        }
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

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            NSZoomableScrollView {
                ZStack {
                    // Content Layer (defining anchors)
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
                                [DeviceAnchorData(id: "HOST", leading: $0)]
                            }
                    }
                    .padding(600)
                }
                .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                    // Connection Lines (Drawn behind nodes)
                    GeometryReader { proxy in
                        ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                    }
                }
            }

            // Overlays
            VStack {
                Spacer()
                HStack {
                    LegendBox().padding(40)
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

// MARK: - Native Zoomable ScrollView

public struct NSZoomableScrollView<Content: View>: NSViewRepresentable {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 10.0
        scrollView.minMagnification = 0.1
        scrollView.drawsBackground = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView

        // Use proper constraints to allow scrolling
        hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor).isActive = true
        hostingView.leftAnchor.constraint(equalTo: scrollView.contentView.leftAnchor).isActive = true
        hostingView.widthAnchor.constraint(greaterThanOrEqualToConstant: 4000).isActive = true
        hostingView.heightAnchor.constraint(greaterThanOrEqualToConstant: 3000).isActive = true

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context _: Context) {
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
                    [DeviceAnchorData(id: device.id, trailing: $0)]
                }
                .anchorPreference(key: DeviceAnchorKey.self, value: .leading) {
                    [DeviceAnchorData(id: device.id, leading: $0)]
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
            // Main Chassis
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.25)], startPoint: .top, endPoint: .bottom))
                .frame(width: 380, height: 260)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 15)

            VStack(spacing: 15) {
                // Screen Area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(width: 340, height: 140)

                    Circle().fill(Color.blue.opacity(0.1)).blur(radius: 30).frame(width: 150)

                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1)
                }

                // Keyboard area well
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 300, height: 45)

                // Trackpad
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 110, height: 35)
            }
            .padding(.top, 10)

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
