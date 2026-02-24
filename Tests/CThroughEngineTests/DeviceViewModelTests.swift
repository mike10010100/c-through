@testable import CThroughEngine
import XCTest

final class DeviceViewModelTests: XCTestCase {
    func testFindDevice() {
        let child = USBDevice(id: "child", name: "Child")
        let parent = USBDevice(id: "parent", name: "Parent", children: [child])
        let root = USBDevice(id: "root", name: "Root", children: [parent])

        let explorer = MockUSBExplorer()
        let viewModel = DeviceViewModel(explorer: explorer)

        XCTAssertNotNil(viewModel.findDevice(id: "child", in: [root]))
        XCTAssertNotNil(viewModel.findDevice(id: "parent", in: [root]))
        XCTAssertNotNil(viewModel.findDevice(id: "root", in: [root]))
        XCTAssertNil(viewModel.findDevice(id: "missing", in: [root]))
    }

    func testRefreshUpdatesDevices() {
        let explorer = MockUSBExplorer()
        let viewModel = DeviceViewModel(explorer: explorer)

        let newDevice = USBDevice(id: "new", name: "New Device")
        explorer.mockDevices = [newDevice]

        let expectation = XCTestExpectation(description: "Refresh updates devices")
        
        viewModel.refresh()
        
        // Refresh is async, we need to wait a bit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(viewModel.devices.count, 1)
            XCTAssertEqual(viewModel.devices.first?.id, "new")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    func testSelectedDeviceMaintainedAfterRefresh() {
        let explorer = MockUSBExplorer()
        let initialDevice = USBDevice(id: "1", name: "Device 1")
        explorer.mockDevices = [initialDevice]
        
        let viewModel = DeviceViewModel(explorer: explorer)
        viewModel.selectedDevice = initialDevice
        
        let updatedDevice = USBDevice(id: "1", name: "Device 1 Updated")
        explorer.mockDevices = [updatedDevice]
        
        let expectation = XCTestExpectation(description: "Selected device maintained")
        
        viewModel.refresh()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(viewModel.selectedDevice)
            XCTAssertEqual(viewModel.selectedDevice?.name, "Device 1 Updated")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
