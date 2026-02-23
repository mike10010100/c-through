@testable import CThroughEngine
import XCTest

class MockUSBExplorer: USBExplorerProtocol {
    var mockDevices: [USBDevice] = []

    func fetchTopology() -> [USBDevice] {
        return mockDevices
    }
}

final class USBExplorerTests: XCTestCase {
    func testMockFetch() {
        let mock = MockUSBExplorer()
        mock.mockDevices = [
            USBDevice(id: "1", name: "Test Device", negotiatedSpeedMbps: 5000.0, maxCapableSpeedMbps: 10000.0)
        ]

        let explorer: USBExplorerProtocol = mock
        let topology = explorer.fetchTopology()

        XCTAssertEqual(topology.count, 1)
        XCTAssertEqual(topology[0].name, "Test Device")
        XCTAssertTrue(topology[0].isBottlenecked)
    }
}
