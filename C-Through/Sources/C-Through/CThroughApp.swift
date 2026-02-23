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
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var magnifyBy = 1.0

    var body: some View {
        ZStack {
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .center, spacing: 0) {
                    // Devices and Hubs
                    VStack(alignment: .trailing, spacing: 60) {
                        if viewModel.devices.isEmpty {
                            VStack {
                                Text("No USB devices found.")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Button("Try Refreshing") { viewModel.refresh() }
                                    .buttonStyle(.link)
                            }
                        } else {
                            ForEach(viewModel.devices) { device in
                                HStack(spacing: 0) {
                                    DeviceTreeBranch(device: device)
                                    
                                    // Connection into the host
                                    TreeLine(isBottlenecked: device.isBottlenecked, speed: device.negotiatedSpeedMbps)
                                        .frame(width: 80, height: 100)
                                }
                            }
                        }
                    }
                    .padding(.leading, 150)

                    // Host MacBook graphic (right side)
                    HostMacBookNode()
                        .padding(.trailing, 150)
                }
                .padding(100)
                .scaleEffect(zoomScale * magnifyBy)
                .frame(minWidth: 1600, minHeight: 1200, alignment: .trailing)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .gesture(
                MagnificationGesture()
                    .updating($magnifyBy) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale *= value
                    }
            )

            // Legend Overlay (Bottom Left)
            VStack {
                Spacer()
                HStack {
                    LegendBox()
                        .padding(40)
                    Spacer()
                }
            }
            
            // Subtle Zoom Indicator (Top Right)
            if zoomScale != 1.0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(Int(zoomScale * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.3)))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(20)
                    }
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
}

struct DeviceTreeBranch: View {
    let device: USBDevice

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Children of this Hub (to the left)
            if !device.children.isEmpty {
                VStack(alignment: .trailing, spacing: 24) {
                    ForEach(device.children) { child in
                        HStack(spacing: 0) {
                            DeviceTreeBranch(device: child)
                            
                            // Horizontal line out of child
                            TreeLine(isBottlenecked: child.isBottlenecked, speed: child.negotiatedSpeedMbps)
                                .frame(width: 40, height: 20)
                        }
                    }
                }
                
                // Vertical trunk connecting all children
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 4)
                        .padding(.vertical, 30)
                    
                    // Line into the parent hub
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 30, height: 4)
                }
                .frame(width: 34)
            }

            // The Card itself
            DeviceCardView(device: device)
        }
    }
}

/// A custom shape that draws the connection lines with proper thickness
struct TreeLine: View {
    let isBottlenecked: Bool
    let speed: Double?
    
    var body: some View {
        Rectangle()
            .fill(isBottlenecked ? Color.red : Color.gray.opacity(0.6))
            .frame(height: thickness)
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

struct DeviceCardView: View {
    let device: USBDevice

    var body: some View {
        HStack(spacing: 0) {
            // Icon Square
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 48, height: 48)

                Image(systemName: iconFor(device))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                if let mfr = device.manufacturer {
                    Text(mfr)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 10)

            Spacer(minLength: 10)

            // Negotiated Speed
            if let speed = device.negotiatedSpeedMbps {
                Text("\(Int(speed))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(device.isBottlenecked ? .red : .primary.opacity(0.6))
                    .padding(.trailing, 15)
            }
        }
        .frame(width: 280, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(device.isBottlenecked ? Color.red.opacity(0.9) : Color.white.opacity(0.1), lineWidth: device.isBottlenecked ? 2.5 : 1)
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
            // Main Chassis (Space Gray)
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 320, height: 220)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

            // The Screen Area (Active/Lit)
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(white: 0.1), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: 280, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LinearGradient(colors: [.blue.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .offset(y: -35)
            
            // Content on the screen (Desktop feel)
            Circle()
                .fill(Color.blue.opacity(0.2))
                .blur(radius: 20)
                .frame(width: 100, height: 100)
                .offset(x: 60, y: -40)

            // Keyboard area
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.4))
                .frame(width: 240, height: 40)
                .offset(y: 55)

            // Trackpad
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .frame(width: 80, height: 30)
                .offset(y: 90)

            // Ports (Visible on the side)
            VStack(spacing: 24) {
                Capsule().fill(Color.black).frame(width: 5, height: 18)
                Capsule().fill(Color.black).frame(width: 5, height: 18)
            }
            .offset(x: -158, y: -30)
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
