@testable import CThroughEngine
import Foundation

class MockUSBExplorer: USBExplorerProtocol {
    var mockDevices: [USBDevice] = []
    func fetchTopology() -> [USBDevice] { return mockDevices }
    func startMonitoring(onChange: @escaping () -> Void) {}
    func stopMonitoring() {}
    func eject(device: USBDevice) {}
}
