@testable import CThroughEngine
import XCTest

final class UIComponentsTests: XCTestCase {
    func testIconFor() {
        let keyboard = USBDevice(id: "1", name: "Apple Magic Keyboard")
        XCTAssertEqual(iconFor(keyboard), "keyboard.fill")

        let ssd = USBDevice(id: "2", name: "PSSD T7")
        XCTAssertEqual(iconFor(ssd), "externaldrive.fill")

        let hub = USBDevice(id: "3", name: "USB Hub")
        XCTAssertEqual(iconFor(hub), "cable.connector")

        let unknown = USBDevice(id: "4", name: "Mystery Box")
        XCTAssertEqual(iconFor(unknown), "usb.fill")
    }

    func testFormatSpeed() {
        XCTAssertEqual(formatSpeed(480.0), "480 Mbps")
        XCTAssertEqual(formatSpeed(5000.0), "5.0 Gbps")
        XCTAssertEqual(formatSpeed(40000.0), "40.0 Gbps")
        XCTAssertEqual(formatSpeed(nil), "Unknown")
    }
}
