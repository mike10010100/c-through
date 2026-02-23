import CThroughEngine
import SwiftUI

// MARK: - Preferences for Line Routing

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
                .background(Color(NSColor.windowBackgroundColor))
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh") { viewModel.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
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
            // Main Drawing Area
            GeometryReader { _ in
                ZStack {
                    Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                    // The Entire Diagram
                    ZStack {
                        // 1. Connection Lines (Bottom Layer)
                        GeometryReader { proxy in
                            ZStack {
                                // Draw lines using anchors
                                ConnectionLayer(devices: viewModel.devices, proxy: proxy)
                            }
                        }

                        // 2. Nodes Layer
                        HStack(alignment: .center, spacing: 120) {
                            // Tree of Devices
                            VStack(alignment: .trailing, spacing: 60) {
                                if viewModel.devices.isEmpty {
                                    Text("No USB devices found.").foregroundColor(.secondary)
                                } else {
                                    ForEach(viewModel.devices) { device in
                                        DeviceTreeBranch(device: device)
                                    }
                                }
                            }

                            // The Host MacBook
                            HostMacBookNode()
                                .anchorPreference(key: DeviceAnchorKey.self, value: .center) {
                                    [DeviceAnchorData(id: "HOST", center: $0)]
                                }
                        }
                    }
                    .scaleEffect(zoomScale)
                    .offset(x: offset.width, y: offset.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            }

            // UI Overlays
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    LegendBox().padding(40)
                    Spacer()
                    // Zoom readout
                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(8)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(40)
                }
            }
        }
    }
}

// MARK: - Line Routing

struct ConnectionLayer: View {
    let devices: [USBDevice]
    let proxy: GeometryProxy

    var body: some View {
        ZStack {
            // Lines to Host
            ForEach(devices) { device in
                LineConnector(from: device.id, to: "HOST", speed: device.negotiatedSpeedMbps, isBottlenecked: device.isBottlenecked)

                // Recursive lines for children
                DeviceChildLines(device: device)
            }
        }
        .overlayPreferenceValue(DeviceAnchorKey.self) { _ in
            // This is handled inside LineConnector via the same preference value
            Color.clear
        }
    }
}

struct DeviceChildLines: View {
    let device: USBDevice
    var body: some View {
        ZStack {
            ForEach(device.children) { child in
                LineConnector(from: child.id, to: device.id, speed: child.negotiatedSpeedMbps, isBottlenecked: child.isBottlenecked)
                DeviceChildLines(device: child)
            }
        }
    }
}

struct LineConnector: View {
    let from: String
    let to: String
    let speed: Double?
    let isBottlenecked: Bool

    var body: some View {
        GeometryReader { proxy in
            Color.clear.overlayPreferenceValue(DeviceAnchorKey.self) { anchors in
                if let fromAnchor = anchors.first(where: { $0.id == from }),
                   let toAnchor = anchors.first(where: { $0.id == to }) {
                    let p1 = proxy[fromAnchor.center]
                    let p2 = proxy[toAnchor.center]

                    Path { path in
                        path.move(to: p1)
                        // Smooth cubic bezier for organic "cable" look
                        let control1 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p1.y)
                        let control2 = CGPoint(x: p1.x + (p2.x - p1.x) / 2, y: p2.y)
                        path.addCurve(to: p2, control1: control1, control2: control2)
                    }
                    .stroke(
                        isBottlenecked ? Color.red : Color.gray.opacity(0.5),
                        lineWidth: thickness
                    )
                }
            }
        }
    }

    private var thickness: CGFloat {
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
        HStack(alignment: .center, spacing: 80) {
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
                    .frame(width: 50, height: 50)
                Image(systemName: iconFor(device))
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .padding(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 15, weight: .bold))
                if let mfr = device.manufacturer {
                    Text(mfr).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 30)
            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))").font(.system(size: 11, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .secondary)
                    .padding(.trailing, 15)
            }
        }
        .frame(width: 300, height: 74)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(device.isBottlenecked ? Color.red : Color.gray.opacity(0.2), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }

    private func iconFor(_ device: USBDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("hub") { return "cable.connector" }
        if name.contains("ssd") || name.contains("drive") { return "externaldrive.fill" }
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse") || name.contains("trackpad") { return "mouse.fill" }
        if name.contains("display") { return "desktopcomputer" }
        return "usb.fill"
    }
}

// MARK: - Host MacBook Node

struct HostMacBookNode: View {
    var body: some View {
        ZStack {
            // Main Chassis (Space Gray Aluminum)
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 280)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 15)

            // The Screen (Black Mirror)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 360, height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .overlay(
                        Circle().fill(Color.blue.opacity(0.15)).blur(radius: 40).frame(width: 150)
                    )

                Spacer()
            }
            .padding(.top, 20)

            // Keyboard Area
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
                .frame(width: 320, height: 60)
                .offset(y: 75)

            // Trackpad
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
                .frame(width: 140, height: 45)
                .offset(y: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05), lineWidth: 1).offset(y: 110))

            // Thunderbolt Ports (Left side)
            VStack(spacing: 35) {
                Capsule().fill(Color.black).frame(width: 6, height: 20)
                Capsule().fill(Color.black).frame(width: 6, height: 20)
            }
            .offset(x: -198, y: -20)
        }
    }
}

// MARK: - Legend

struct LegendBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LegendRow(speed: "1.5 Mbps", label: "USB 1.0", weight: 1.5)
            LegendRow(speed: "480 Mbps", label: "USB 2.0", weight: 3.0)
            LegendRow(speed: "5,000 Mbps", label: "USB 3.0", weight: 5.0)
            LegendRow(speed: "10,000 Mbps", label: "USB 3.1", weight: 7.0)
            LegendRow(speed: "40,000 Mbps", label: "Thunderbolt 3", weight: 10.0)
            Divider().padding(.vertical, 5)
            HStack {
                Capsule().fill(Color.red).frame(width: 45, height: 5)
                Text("Limited by cable throughput").font(.caption).foregroundColor(.red)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.2), radius: 15)
    }
}

struct LegendRow: View {
    let speed: String; let label: String; let weight: CGFloat
    var body: some View {
        HStack {
            Capsule().fill(Color.gray.opacity(0.5)).frame(width: 45, height: weight)
            Text(speed).font(.system(size: 11, design: .monospaced))
            Spacer()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(width: 200)
    }
}
