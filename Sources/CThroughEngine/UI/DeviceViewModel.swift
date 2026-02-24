import Combine
import SwiftUI

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
