import SwiftUI

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
        VStack(spacing: 0) {
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
}
