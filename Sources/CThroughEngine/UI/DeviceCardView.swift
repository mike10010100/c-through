import SwiftUI

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
        .frame(width: UIConstants.cardWidth, height: UIConstants.cardHeight)
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
