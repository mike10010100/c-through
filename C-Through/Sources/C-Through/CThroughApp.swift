import CThroughEngine
import SwiftUI

@main
struct CThroughApp: App {
    @StateObject private var viewModel = DeviceViewModel(explorer: USBExplorer())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 800)
                .background(Color(NSColor.windowBackgroundColor))
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

struct ContentView: View {
    @ObservedObject var viewModel: DeviceViewModel
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Main Canvas Area
            GeometryReader { _ in
                ZStack {
                    Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                    // The Diagram Content
                    Group {
                        HStack(alignment: .center, spacing: 100) {
                            // Tree of Devices
                            VStack(alignment: .trailing, spacing: 50) {
                                if viewModel.devices.isEmpty {
                                    Text("No USB devices found.").foregroundColor(.secondary)
                                } else {
                                    ForEach(viewModel.devices) { device in
                                        DeviceTreeBranch(device: device)
                                    }
                                }
                            }

                            // The Host
                            HostMacBookNode()
                        }
                    }
                    .scaleEffect(zoomScale)
                    .offset(x: offset.width, y: offset.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // Panning Gesture
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                // Zoom Gesture
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = value.magnitude
                        }
                )
            }

            // Legend Overlay (Bottom Left)
            VStack {
                Spacer()
                HStack {
                    LegendBox()
                        .padding(30)
                    Spacer()
                }
            }

            // Floating Refresh Button
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

struct DeviceTreeBranch: View {
    let device: USBDevice

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Children to the left
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 20) {
                    ForEach(device.children) { child in
                        HStack(spacing: 0) {
                            DeviceTreeBranch(device: child)
                            ConnectorLine(isBottlenecked: child.isBottlenecked, speed: child.negotiatedSpeedMbps)
                                .frame(width: 40)
                        }
                    }
                }

                // Vertical trunk
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 20)

                // Short stub into parent
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 20, height: 2)
            }

            DeviceCardView(device: device)
        }
    }
}

struct ConnectorLine: View {
    let isBottlenecked: Bool
    let speed: Double?

    var body: some View {
        Rectangle()
            .fill(isBottlenecked ? Color.red : Color.gray.opacity(0.4))
            .frame(height: thickness)
    }

    private var thickness: CGFloat {
        let s = speed ?? 480.0
        if s <= 12.0 { return 1.0 }
        if s <= 480.0 { return 2.0 }
        if s <= 5000.0 { return 4.0 }
        if s <= 10000.0 { return 6.0 }
        return 8.0
    }
}

struct DeviceCardView: View {
    let device: USBDevice

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .frame(width: 44, height: 44)
                Image(systemName: iconFor(device))
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                if let mfr = device.manufacturer {
                    Text(mfr)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 20)

            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .secondary)
                    .padding(.trailing, 10)
            }
        }
        .frame(width: 260, height: 64)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.isBottlenecked ? Color.red : Color.gray.opacity(0.2), lineWidth: device.isBottlenecked ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private func iconFor(_ device: USBDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("hub") { return "cable.connector" }
        if name.contains("ssd") || name.contains("drive") { return "externaldrive.fill" }
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse") || name.contains("trackpad") { return "mouse.fill" }
        if name.contains("display") { return "desktopcomputer" }
        if name.contains("camera") { return "camera.fill" }
        return "usb.fill"
    }
}

struct HostMacBookNode: View {
    var body: some View {
        ZStack {
            // Laptop Base
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                .frame(width: 340, height: 240)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

            // Screen
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .frame(width: 300, height: 140)
                .offset(y: -35)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        .offset(y: -35)
                )

            // Screen Content (Mock Desktop)
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 280, height: 120)
                .offset(y: -35)
                .blur(radius: 5)

            // Keyboard
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.5))
                .frame(width: 260, height: 50)
                .offset(y: 65)

            // Trackpad
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .frame(width: 100, height: 40)
                .offset(y: 95)

            // Connection Ports
            VStack(spacing: 30) {
                RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 4, height: 16)
                RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 4, height: 16)
            }
            .offset(x: -170, y: -20)
        }
    }
}

struct LegendBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LegendRow(speed: "1.5 Mbps", label: "USB 1.0", weight: 1.0)
            LegendRow(speed: "480 Mbps", label: "USB 2.0", weight: 2.0)
            LegendRow(speed: "5,000 Mbps", label: "USB 3.0", weight: 4.0)
            LegendRow(speed: "10,000 Mbps", label: "USB 3.1", weight: 6.0)
            LegendRow(speed: "40,000 Mbps", label: "Thunderbolt 3", weight: 8.0)
            Divider().padding(.vertical, 4)
            HStack {
                Capsule().fill(Color.red).frame(width: 40, height: 4)
                Text("Limited by cable throughput").font(.caption2).foregroundColor(.red)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
}

struct LegendRow: View {
    let speed: String; let label: String; let weight: CGFloat
    var body: some View {
        HStack {
            Capsule().fill(Color.gray.opacity(0.6)).frame(width: 40, height: weight)
            Text(speed).font(.system(size: 10, design: .monospaced))
            Spacer()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(width: 180)
    }
}
