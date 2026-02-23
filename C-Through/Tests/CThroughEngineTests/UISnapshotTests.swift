import XCTest
import SwiftUI
@testable import CThroughEngine

final class UISnapshotTests: XCTestCase {
    func testMainViewAtDifferentScales() {
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
        
        // Test 100% Scale
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
        
        if let image = view.snapshot(size: CGSize(width: 1400, height: 1000)) {
            let path = saveSnapshot(image, name: "final_verification_100.png")
            print("100% Snapshot saved to: \(path ?? "unknown")")
        }
        
        // Test 50% Scale
        if let image = view.scaleEffect(0.5).snapshot(size: CGSize(width: 700, height: 500)) {
            let path = saveSnapshot(image, name: "final_verification_50.png")
            print("50% Snapshot saved to: \(path ?? "unknown")")
        }
    }
}
