import AppKit
import CThroughEngine
import SwiftUI

// MARK: - Preferences

public struct DeviceAnchorData: Equatable {
    public let id: String
    public var bounds: Anchor<CGRect>
    
    public init(id: String, bounds: Anchor<CGRect>) {
        self.id = id
        self.bounds = bounds
    }
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

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            // THE BULLETPROOF NATIVE ZOOM: NSScrollView wrapper
            // This is the ONLY way to get native macOS pinch-to-zoom and scroll-zoom.
            NativeZoomableCanvas {
                ZStack {
                    // Huge clear background to define coordinate space
                    Color.clear.frame(width: 4000, height: 3000)
                    
                    // THE CONTENT
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
                            .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                                [DeviceAnchorData(id: "HOST", bounds: $0)]
                            }
                    }
                }
                // IMPORTANT: Connection lines must be drawn INSIDE the hosting view 
                // so they share the same anchor resolution coordinate space.
                .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                    GeometryReader { proxy in
                        ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                    }
                }
            }

            // Overlays (floating UI)
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

// MARK: - Native Zoomable Canvas (The Core fix)

struct NativeZoomableCanvas<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true // THIS enables pinch-to-zoom
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 10.0
        scrollView.minMagnification = 0.1
        scrollView.drawsBackground = false
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Fixed massive frame for the internal content
        hostingView.frame = NSRect(x: 0, y: 0, width: 4000, height: 3000)
        scrollView.documentView = hostingView
        
        // Scroll to center initially so the user starts at the MacBook
        DispatchQueue.main.async {
            let contentSize = hostingView.frame.size
            let visibleSize = scrollView.contentView.bounds.size
            let scrollPoint = NSPoint(x: (contentSize.width - visibleSize.width) / 2 + 500,
                                     y: (contentSize.height - visibleSize.height) / 2)
            scrollView.contentView.scroll(to: scrollPoint)
        }

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
        HStack(alignment: .center, spacing: 150) {
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 40) {
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
            // Main Chassis (Space Gray Aluminum)
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.3)], startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 280)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.2), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 15)

            VStack(spacing: 20) {
                // Screen Area (Larger and more distinct)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black)
                    .frame(width: 360, height: 160)
                    .overlay(
                        ZStack {
                            // Desktop Glow
                            Circle().fill(Color.blue.opacity(0.15)).blur(radius: 40).frame(width: 200)
                            // Subtle Screen Frame
                            RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                    )
                
                // Keyboard area well
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 320, height: 50)
                
                // Trackpad
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 140, height: 40)
            }
            .offset(y: -10)
            
            // Physical Port Indents on the left
            VStack(spacing: 40) {
                Capsule().fill(Color.black).frame(width: 6, height: 22)
                Capsule().fill(Color.black).frame(width: 6, height: 22)
            }
            .offset(x: -200, y: -30)
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
