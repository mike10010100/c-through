import CThroughEngine
import SwiftUI

@main
struct CThroughApp: App {
    @StateObject private var viewModel = DeviceViewModel(explorer: USBExplorer())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1000, minHeight: 800)
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

    var body: some View {
        ZStack {
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .center, spacing: 0) {
                    // Devices and Hubs
                    VStack(alignment: .trailing, spacing: 40) {
                        if viewModel.devices.isEmpty {
                            Text("No USB devices found.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(viewModel.devices) { device in
                                HStack(spacing: 0) {
                                    DeviceTreeBranch(device: device)
                                    // Line into host
                                    Rectangle()
                                        .fill(device.isBottlenecked ? Color.red : Color.gray.opacity(0.8))
                                        .frame(width: 40, height: lineThickness(for: device.negotiatedSpeedMbps))
                                }
                            }
                        }
                    }
                    .padding(.leading, 100)

                    // Host MacBook graphic (right side)
                    HostMacBookNode()
                        .padding(.trailing, 100)
                }
                .padding(40)
                .frame(minWidth: 1000, minHeight: 800, alignment: .trailing)
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
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("C-Through").font(.headline)
            }
            ToolbarItem {
                Button(action: viewModel.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func lineThickness(for speed: Double?) -> CGFloat {
        let s = speed ?? 480.0
        if s <= 12.0 { return 1.0 }
        if s <= 480.0 { return 2.0 }
        if s <= 5000.0 { return 4.0 }
        if s <= 10000.0 { return 6.0 }
        return 8.0
    }
}

struct DeviceTreeBranch: View {
    let device: USBDevice

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Children of this Hub (to the left)
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 16) {
                    ForEach(device.children) { child in
                        HStack(spacing: 0) {
                            DeviceTreeBranch(device: child)

                            // Horizontal line out of the child
                            Rectangle()
                                .fill(child.isBottlenecked ? Color.red : Color.gray.opacity(0.8))
                                .frame(width: 30, height: lineThickness(for: child.negotiatedSpeedMbps))
                        }
                    }
                }

                // Vertical trunk connecting all children
                Rectangle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 4, height: CGFloat(max(1, device.children.count)) * 40)

                // Horizontal line into the parent
                Rectangle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 30, height: 4)
            }

            // The Card itself
            DeviceCardView(device: device)
        }
    }

    private func lineThickness(for speed: Double?) -> CGFloat {
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
            // Icon Square
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 44, height: 44)

                Image(systemName: iconFor(device))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                if let mfr = device.manufacturer {
                    Text(mfr)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 10)

            Spacer(minLength: 5)

            // Negotiated Speed
            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .secondary)
                    .padding(.trailing, 10)
            }
        }
        .frame(width: 260, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.isBottlenecked ? Color.red.opacity(0.8) : Color.gray.opacity(0.2), lineWidth: 1.5)
        )
    }

    private func iconFor(_ device: USBDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("hub") { return "cable.connector" }
        if name.contains("ssd") || name.contains("drive") { return "externaldrive.fill" }
        if name.contains("keyboard") || name.contains("dk5qs") { return "keyboard.fill" }
        if name.contains("mouse") || name.contains("trackpad") || name.contains("receiver") { return "mouse.fill" }
        if name.contains("display") { return "desktopcomputer" }
        if name.contains("headset") || name.contains("audio") { return "headphones" }
        if name.contains("lan") || name.contains("ethernet") { return "network" }
        if name.contains("camera") || name.contains("brio") { return "camera.fill" }
        if name.contains("mic") || name.contains("yeti") { return "mic.fill" }
        return "usb.fill"
    }
}

struct HostMacBookNode: View {
    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.systemGray).opacity(0.8))
                .frame(width: 250, height: 180)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            // Keyboard well
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.darkGray).opacity(0.6))
                .frame(width: 210, height: 90)
                .offset(y: -25)

            // Trackpad
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.darkGray).opacity(0.5))
                .frame(width: 90, height: 50)
                .offset(y: 55)

            // Ports on left edge
            VStack(spacing: 30) {
                Capsule().fill(.black.opacity(0.8)).frame(width: 6, height: 16)
                Capsule().fill(.black.opacity(0.8)).frame(width: 6, height: 16)
            }
            .offset(x: -125, y: -20)
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 10)
        )
    }
}

struct LegendRow: View {
    let speed: String
    let label: String
    let weight: CGFloat

    var body: some View {
        HStack {
            Capsule()
                .fill(Color.gray.opacity(0.6))
                .frame(width: 40, height: weight)
            Text(speed).font(.system(size: 10, design: .monospaced))
            Spacer()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(width: 180)
    }
}
