@testable import CThroughEngine
import XCTest
import IOKit
import IOKit.usb

class MockIORegistryProvider: IORegistryProvider {
    var mockDevices: [UInt64: [String: Any]] = [:]
    var mockParents: [UInt64: UInt64] = [:]
    var matchingServiceIds: [UInt64] = []
    
    private var matchingIndex = 0

    func getMatchingServices(_ matchingDict: CFDictionary) -> io_iterator_t {
        return 100 // Dummy
    }

    func getRegistryEntryID(_ service: io_service_t) -> UInt64 {
        return UInt64(service)
    }

    func getParentEntry(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_registry_entry_t {
        return io_registry_entry_t(mockParents[UInt64(service)] ?? 0)
    }

    func conformsTo(_ service: io_object_t, _ className: String) -> Bool {
        return className == kIOUSBDeviceClassName || className == "IOUSBHostDevice"
    }

    func createCFProperty(_ service: io_registry_entry_t, _ key: String) -> AnyObject? {
        return mockDevices[UInt64(service)]?[key] as AnyObject?
    }

    func getChildIterator(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_iterator_t {
        return 0 // For now
    }

    func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        guard matchingIndex < matchingServiceIds.count else { return 0 }
        let val = matchingServiceIds[matchingIndex]
        matchingIndex += 1
        return io_service_t(val)
    }

    func objectRelease(_ object: io_object_t) {}
    func objectRetain(_ object: io_object_t) {}
}

final class USBExplorerTests: XCTestCase {
    func testFetchTopologyAssemblesTree() {
        let provider = MockIORegistryProvider()
        
        // Setup: Root Hub (1) -> Device (2)
        provider.matchingServiceIds = [1, 2]
        provider.mockParents[2] = 1
        
        provider.mockDevices[1] = [
            kUSBProductString: "Root Hub",
            "Device Speed": UInt32(kUSBDeviceSpeedSuper)
        ]
        provider.mockDevices[2] = [
            kUSBProductString: "External Drive",
            "Device Speed": UInt32(kUSBDeviceSpeedHigh)
        ]
        
        let explorer = USBExplorer(provider: provider)
        let topology = explorer.fetchTopology()
        
        XCTAssertEqual(topology.count, 1)
        XCTAssertEqual(topology[0].name, "Root Hub")
        XCTAssertEqual(topology[0].children.count, 1)
        XCTAssertEqual(topology[0].children[0].name, "External Drive")
    }
}
