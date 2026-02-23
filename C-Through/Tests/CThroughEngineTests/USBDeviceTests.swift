@testable import CThroughEngine
import XCTest

final class USBDeviceTests: XCTestCase {
    func testBottleneckDetection() {
        let slowDevice = USBDevice(
            id: "1",
            name: "Slow Drive",
            negotiatedSpeedMbps: 480.0,
            maxCapableSpeedMbps: 10000.0
        )
        XCTAssertTrue(slowDevice.isBottlenecked)

        let fastDevice = USBDevice(
            id: "2",
            name: "Fast Drive",
            negotiatedSpeedMbps: 10000.0,
            maxCapableSpeedMbps: 10000.0
        )
        XCTAssertFalse(fastDevice.isBottlenecked)
    }

    func testEquality() {
        let device1 = USBDevice(id: "1", name: "A")
        let device2 = USBDevice(id: "1", name: "B")
        XCTAssertEqual(device1, device2) // ID-based equality check for model

        let device3 = USBDevice(id: "2", name: "A")
        XCTAssertNotEqual(device1, device3)
    }
}
