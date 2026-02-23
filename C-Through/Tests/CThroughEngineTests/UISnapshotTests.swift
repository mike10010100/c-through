@testable import CThroughEngine
import SwiftUI
import XCTest

final class UISnapshotTests: XCTestCase {
    func testMainViewSnapshot() {
        let explorer = MockUSBExplorer()
        explorer.mockDevices = [
            USBDevice(
                id: "1",
                name: "Studio Display",
                manufacturer: "Apple Inc.",
                negotiatedSpeedMbps: 40000,
                maxCapableSpeedMbps: 40000,
                children: [
                    USBDevice(
                        id: "2",
                        name: "Keyboard",
                        manufacturer: "Apple",
                        negotiatedSpeedMbps: 480,
                        maxCapableSpeedMbps: 480
                    )
                ]
            ),
            USBDevice(
                id: "3",
                name: "PSSD T9",
                manufacturer: "Samsung",
                negotiatedSpeedMbps: 480,
                maxCapableSpeedMbps: 10000
            )
        ]

        let viewModel = DeviceViewModel(explorer: explorer)

        // Use a container that resolves anchors correctly for the snapshot
        let view = ZStack {
            Color.black.ignoresSafeArea()

            ZStack {
                HStack(alignment: .center, spacing: 200) {
                    VStack(alignment: .trailing, spacing: 80) {
                        ForEach(viewModel.devices) { device in
                            DeviceTreeBranch(device: device)
                        }
                    }
                    HostMacBookNode()
                        .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                            [DeviceAnchorData(id: "HOST", bounds: $0)]
                        }
                }
                .padding(200)
            }
            .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    ConnectionLinesView(anchors: anchors, devices: viewModel.devices, proxy: proxy)
                }
            }
        }

        // Headless rendering of anchors often requires multiple passes or a real window.
        // For the purpose of this prototype, we'll render it at a fixed size.
        if let image = view.snapshot(size: CGSize(width: 1400, height: 1000)) {
            let path = saveSnapshot(image, name: "final_snapshot.png")
            print("Snapshot saved to: \(path ?? "unknown")")
        }
    }
}
