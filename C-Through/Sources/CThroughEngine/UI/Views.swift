import AppKit
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
    @State private var cachedAnchors: [DeviceAnchorData] = []

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            GeometryReader { proxy in
                NativeZoomableCanvas {
                    ZStack {
                        // Dynamically size to at least the window, but allow expanding
                        Color.clear.frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height
                        )

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
                    .contentShape(Rectangle()) // Ensure the entire padded area is interactive
                    // Generous padding creates the "infinite canvas" feel around the content
                    .padding(1000)
                    .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                        GeometryReader { geo in
                            // Use cached anchors when current ones are empty (happens during
                            // a refresh re-render before preferences are repopulated).
                            let resolvedAnchors = anchors.isEmpty ? cachedAnchors : anchors
                            ConnectionLinesView(anchors: resolvedAnchors, devices: viewModel.devices, proxy: geo)
                                .onChange(of: anchors.isEmpty) {
                                    if !anchors.isEmpty { cachedAnchors = anchors }
                                }
                        }
                    }
                }
            }

            // Overlays (floating UI)
            VStack {
                Spacer()
                HStack {
                    LegendBox().padding(20)
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

// MARK: - AppKit Subclasses

/// NSHostingView subclass that forwards magnify (pinch) events to its parent scroll view
/// instead of letting SwiftUI consume them silently.
private class CanvasHostingView<Content: View>: NSHostingView<Content> {
    weak var parentScrollView: CanvasScrollView?

    override func magnify(with event: NSEvent) {
        if let parentScrollView {
            parentScrollView.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
}

private class CanvasScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            let factor = delta > 0 ? 1.05 : 0.95
            let newMag = max(minMagnification, min(maxMagnification, magnification * factor))
            
            // Native setMagnification expects a point in the DOCUMENT view's coordinate system
            if let docView = documentView {
                let pointInDoc = docView.convert(event.locationInWindow, from: nil)
                setMagnification(newMag, centeredAt: pointInDoc)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        let newMag = max(minMagnification, min(maxMagnification, magnification * (1 + event.magnification)))
        if let docView = documentView {
            let pointInDoc = docView.convert(event.locationInWindow, from: nil)
            setMagnification(newMag, centeredAt: pointInDoc)
        }
    }
}

// MARK: - Native Zoomable Canvas

struct NativeZoomableCanvas<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Bring app to front (diagnostic for the "backgrounding" issue)
        NSApp.activate(ignoringOtherApps: true)

        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        // Re-enable native magnification support but we still override the triggers
        scrollView.allowsMagnification = true
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 5.0
        scrollView.minMagnification = 0.2
        scrollView.drawsBackground = false

        // Use CanvasHostingView (forwards magnify events to scroll view) as documentView
        // with frame-based layout so magnification transforms aren't fought by Auto Layout.
        let hostingView = CanvasHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.parentScrollView = scrollView
        scrollView.documentView = hostingView

        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView

        // Scroll to center initially so the user starts at the MacBook
        DispatchQueue.main.async {
            let contentSize = hostingView.fittingSize
            hostingView.frame = CGRect(origin: .zero, size: contentSize)

            let visibleSize = scrollView.contentView.bounds.size
            let scrollPoint = NSPoint(
                x: (contentSize.width - visibleSize.width) / 2 + 500,
                y: (contentSize.height - visibleSize.height) / 2
            )
            scrollView.contentView.scroll(to: scrollPoint)
        }

        // Click-and-drag to pan
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scrollView.addGestureRecognizer(pan)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
        }
    }

    class Coordinator: NSObject {
        fileprivate weak var scrollView: CanvasScrollView?
        fileprivate weak var hostingView: CanvasHostingView<Content>?
        private var lastDragLocation: NSPoint = .zero

        @objc
        func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let scrollView else { return }
            let location = gesture.location(in: scrollView)

            switch gesture.state {
            case .began:
                lastDragLocation = location

            case .changed:
                let delta = NSPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
                lastDragLocation = location

                let clipView = scrollView.contentView
                var origin = clipView.bounds.origin
                // NSScrollView is non-flipped (Y increases upward), so drag-down gives negative
                // delta.y. Subtracting it increases origin.y, which scrolls the flipped clip view down.
                origin.x -= delta.x
                origin.y -= delta.y
                let constrainedOrigin = clipView.constrainBoundsRect(
                    NSRect(origin: origin, size: clipView.bounds.size)
                ).origin
                clipView.scroll(to: constrainedOrigin)
                scrollView.reflectScrolledClipView(clipView)

            default:
                break
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
        let mbps = speed ?? 480.0
        if mbps <= 12.0 { return 1.5 }
        if mbps <= 480.0 { return 3.0 }
        if mbps <= 5000.0 { return 5.0 }
        if mbps <= 10000.0 { return 7.0 }
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
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    device.isBottlenecked ? Color.red : Color.white.opacity(0.1),
                    lineWidth: device.isBottlenecked ? 2 : 1
                )
        )
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
        VStack(spacing: 2) {
            // Lid (display)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.42), Color(white: 0.32)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 340, height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 300, height: 185)
                    .overlay(
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .blur(radius: 30)
                                .frame(width: 160)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        }
                    )
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

            // Base (keyboard deck)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.35), Color(white: 0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 370, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 300, height: 40)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 120, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                }

                // USB-C port indents on left side of base
                VStack(spacing: 20) {
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 5, height: 16)
                    Capsule().fill(Color.black.opacity(0.6)).frame(width: 5, height: 16)
                }
                .offset(x: -183)
            }
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
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
        .fixedSize()
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
        .frame(width: 220)
    }
}
