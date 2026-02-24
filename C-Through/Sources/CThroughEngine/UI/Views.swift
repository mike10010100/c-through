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
    @Published public var selectedDevice: USBDevice?
    private let explorer: USBExplorerProtocol
    private let queue = DispatchQueue(label: "com.c-through.explorer", qos: .userInitiated)

    public init(explorer: USBExplorerProtocol) {
        self.explorer = explorer
        refresh()
        explorer.startMonitoring { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        explorer.stopMonitoring()
    }

    public func refresh() {
        queue.async {
            let fetched = self.explorer.fetchTopology()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.devices = fetched
                    // Update selected device if it still exists
                    if let selected = self.selectedDevice {
                        self.selectedDevice = self.findDevice(id: selected.id, in: fetched)
                    }
                }
            }
        }
    }

    private func findDevice(id: String, in devices: [USBDevice]) -> USBDevice? {
        for device in devices {
            if device.id == id { return device }
            if let found = findDevice(id: id, in: device.children) { return found }
        }
        return nil
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
        HStack(spacing: 0) {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                GeometryReader { proxy in
                    NativeZoomableCanvas {
                        ZStack {
                            Color.clear.frame(
                                minWidth: proxy.size.width,
                                minHeight: proxy.size.height
                            )

                            HStack(alignment: .center, spacing: 200) {
                                VStack(alignment: .trailing, spacing: 80) {
                                    if viewModel.devices.isEmpty {
                                        Text("No USB devices found.").foregroundColor(.secondary)
                                    } else {
                                        ForEach(viewModel.devices) { device in
                                            DeviceTreeBranch(device: device, viewModel: viewModel)
                                        }
                                    }
                                }

                                HostMacBookNode()
                                    .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                                        [DeviceAnchorData(id: "HOST", bounds: $0)]
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(1000)
                        .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                            GeometryReader { geo in
                                let resolvedAnchors = anchors.isEmpty ? cachedAnchors : anchors
                                ConnectionLinesView(anchors: resolvedAnchors, devices: viewModel.devices, proxy: geo)
                                    .onChange(of: anchors.isEmpty) {
                                        if !anchors.isEmpty { cachedAnchors = anchors }
                                    }
                            }
                        }
                    }
                }

                // Overlays
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
                        Button(action: { viewModel.refresh() }) {
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
            .onTapGesture {
                withAnimation { viewModel.selectedDevice = nil }
            }

            if let selected = viewModel.selectedDevice {
                InspectorSidebar(device: selected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(width: 320)
            }
        }
    }
}

// MARK: - Inspector

struct InspectorSidebar: View {
    let device: USBDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                                .frame(width: 56, height: 56)
                            Image(systemName: iconFor(device))
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.headline).lineLimit(2)
                            Text(device.manufacturer ?? "Unknown Manufacturer")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 20)

                    if device.isBottlenecked {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Performance Bottleneck").bold()
                            }
                            .foregroundColor(.red)
                            .font(.subheadline)

                            Text("This device is capable of \(Int(device.maxCapableSpeedMbps ?? 0)) Mbps but is only negotiating \(Int(device.negotiatedSpeedMbps ?? 0)) Mbps. This is likely due to an inadequate cable or hub.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
                    }

                    InspectorSection(title: "Connection Details") {
                        InspectorRow(label: "Negotiated Speed", value: formatSpeed(device.negotiatedSpeedMbps))
                        InspectorRow(label: "Max Capability", value: formatSpeed(device.maxCapableSpeedMbps))
                        if let vendorID = device.vendorID {
                            InspectorRow(label: "Vendor ID", value: String(format: "0x%04X", vendorID))
                        }
                        if let productID = device.productID {
                            InspectorRow(label: "Product ID", value: String(format: "0x%04X", productID))
                        }
                    }

                    InspectorSection(title: "Device Info") {
                        InspectorRow(label: "Serial Number", value: device.serialNumber ?? "N/A")
                        InspectorRow(label: "Registry ID", value: device.id)
                    }

                    if device.canEject {
                        Button(action: { /* In a real app, call NSWorkspace.shared.unmountAndEjectDevice */ }) {
                            HStack {
                                Image(systemName: "eject.fill")
                                Text("Eject Device")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1), alignment: .leading)
    }

    private func formatSpeed(_ mbps: Double?) -> String {
        guard let mbps = mbps else { return "Unknown" }
        if mbps >= 1000 {
            return String(format: "%.1f Gbps", mbps / 1000.0)
        }
        return "\(Int(mbps)) Mbps"
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption).bold().foregroundColor(.secondary).textCase(.uppercase)
            VStack(spacing: 0) {
                content
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        Divider().padding(.leading, 12).opacity(0.5)
    }
}

// MARK: - AppKit Subclasses

/// NSHostingView subclass that avoids swallowing gestures we want to handle ourselves.
private class CanvasHostingView<Content: View>: NSHostingView<Content> {
    weak var parentScrollView: CanvasScrollView?
}

private class CanvasScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            let factor = delta > 0 ? 1.1 : 0.9
            let newMag = max(minMagnification, min(maxMagnification, magnification * factor))
            
            if let docView = documentView {
                let pointInDoc = docView.convert(event.locationInWindow, from: nil)
                setMagnification(newMag, centeredAt: pointInDoc)
            }
        } else {
            super.scrollWheel(with: event)
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
        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true 
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 5.0
        scrollView.minMagnification = 0.2
        scrollView.drawsBackground = false

        let hostingView = CanvasHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.parentScrollView = scrollView
        scrollView.documentView = hostingView

        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView

        // Pinch Gesture Recognizer
        let pinch = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scrollView.addGestureRecognizer(pinch)

        // Click-and-drag to pan
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scrollView.addGestureRecognizer(pan)

        // Scroll to center initially
        DispatchQueue.main.async {
            let contentSize = hostingView.fittingSize
            hostingView.frame = CGRect(origin: .zero, size: contentSize)

            let visibleSize = scrollView.contentView.bounds.size
            let scrollPoint = NSPoint(
                x: (contentSize.width - visibleSize.width) / 2 + 500,
                y: (contentSize.height - visibleSize.height) / 2
            )
            scrollView.contentView.scroll(to: scrollPoint)
            
            // Activate app once
            NSApp.activate(ignoringOtherApps: true)
        }

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
        private var initialMagnification: CGFloat = 1.0

        @objc
        func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
            guard let scrollView else { return }
            
            if gesture.state == .began {
                initialMagnification = scrollView.magnification
            }
            
            let newMag = max(scrollView.minMagnification, 
                             min(scrollView.maxMagnification, 
                                 initialMagnification * (1 + gesture.magnification)))
            
            if let docView = scrollView.documentView {
                let pointInDoc = docView.convert(gesture.location(in: scrollView), from: scrollView)
                scrollView.setMagnification(newMag, centeredAt: pointInDoc)
            }
        }

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

                // Thunderbolt indicator (placed near the host/parent side of the cable)
                if device.isThunderbolt {
                    let iconPoint = CGPoint(x: p1.x + (p2.x - p1.x) * 0.8, y: p2.y)
                    context.draw(Image(systemName: "bolt.fill"), at: iconPoint, anchor: .center)
                }

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
    @ObservedObject var viewModel: DeviceViewModel
    var body: some View {
        HStack(alignment: .center, spacing: 150) {
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 40) {
                    ForEach(device.children) { child in
                        DeviceTreeBranch(device: child, viewModel: viewModel)
                    }
                }
            }
            DeviceCardView(device: device, isSelected: viewModel.selectedDevice?.id == device.id)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.selectedDevice = device
                    }
                }
                .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                    [DeviceAnchorData(id: device.id, bounds: $0)]
                }
        }
    }
}

struct DeviceCardView: View {
    let device: USBDevice
    let isSelected: Bool
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
                    isSelected ? Color.blue : (device.isBottlenecked ? Color.red : Color.white.opacity(0.1)),
                    lineWidth: (isSelected || device.isBottlenecked) ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.3 : 0.2), radius: isSelected ? 12 : 8, y: 4)
        .scaleEffect(isSelected ? 1.02 : 1.0)
    }
}

private func iconFor(_ device: USBDevice) -> String {
    let name = device.name.lowercased()
    if name.contains("hub") { return "cable.connector" }
    if name.contains("ssd") || name.contains("drive") || name.contains("external") { return "externaldrive.fill" }
    if name.contains("keyboard") { return "keyboard.fill" }
    if name.contains("mouse") || name.contains("trackpad") || name.contains("receiver") { return "mouse.fill" }
    if name.contains("display") || name.contains("monitor") { return "desktopcomputer" }
    if name.contains("camera") || name.contains("brio") || name.contains("video") { return "camera.fill" }
    if name.contains("mic") || name.contains("yeti") || name.contains("audio") { return "mic.fill" }
    return "usb.fill"
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
