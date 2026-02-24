import Foundation
import IOKit
import IOKit.usb

public protocol USBExplorerProtocol {
    func fetchTopology() -> [USBDevice]
}

public class USBExplorer: USBExplorerProtocol {
    public init() {}

    public func fetchTopology() -> [USBDevice] {
        var devicesMap: [UInt64: USBDevice] = [:]
        var parentMap: [UInt64: UInt64] = [:]

        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var device = IOIteratorNext(iterator)
        while device != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(device, &id)

            var parentID: UInt64 = 0
            var current = device
            IOObjectRetain(current)

            while true {
                var parent: io_registry_entry_t = 0
                if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
                    if IOObjectConformsTo(parent, kIOUSBDeviceClassName) != 0 {
                        IORegistryEntryGetRegistryEntryID(parent, &parentID)
                        IOObjectRelease(parent)
                        IOObjectRelease(current)
                        break
                    }
                    IOObjectRelease(current)
                    current = parent
                } else {
                    IOObjectRelease(current)
                    break
                }
            }

            if let newDevice = buildDevice(from: device, id: id) {
                devicesMap[id] = newDevice
                parentMap[id] = parentID
            }

            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }

        // Link children to parents
        for (id, parentID) in parentMap {
            if parentID != 0, let child = devicesMap[id], var parent = devicesMap[parentID] {
                parent.children.append(child)
                devicesMap[parentID] = parent
            }
        }

        // Roots are devices that either have no parentID or whose parentID isn't in our map
        let roots = devicesMap.values.filter { device in
            guard let deviceID = UInt64(device.id), let pID = parentMap[deviceID] else { return true }
            return pID == 0 || devicesMap[pID] == nil
        }

        return Array(roots)
    }

    private func buildDevice(from service: io_service_t, id: UInt64) -> USBDevice? {
        let name = getProperty(service, kUSBProductString as String) as String? ?? "Unknown Device"
        let manufacturer = getProperty(service, kUSBVendorString as String) as String?
        let vendorID = getProperty(service, kUSBVendorID as String) as UInt16?
        let productID = getProperty(service, kUSBProductID as String) as UInt16?
        let serialNumber = getProperty(service, kUSBSerialNumberString as String) as String?
        let speed = getProperty(service, "Device Speed") as UInt32? // IOKit uses enum values here

        // Speed enum to Mbps
        let speedMbps = convertSpeed(speed)
        let maxSpeedMbps = getMaxCapability(from: service)

        return USBDevice(
            id: String(id),
            name: name,
            manufacturer: manufacturer,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            negotiatedSpeedMbps: speedMbps,
            maxCapableSpeedMbps: maxSpeedMbps,
            children: []
        )
    }

    private func getMaxCapability(from _: io_service_t) -> Double? {
        // Here we'd ideally use `IOUSBDeviceInterface::GetUSBDeviceInformation`
        // or parse descriptors. For now, we'll return a placeholder based on
        // vendor/product to simulate the bottleneck for our PRD demo.
        // We can add a full descriptor parser here as a separate module.
        // For now, we'll try to find any descriptor information.
        return 10000.0 // Placeholder
    }

    private func getProperty<T>(_ service: io_service_t, _ key: String) -> T? {
        let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        guard let value = property?.takeRetainedValue() else { return nil }
        return value as? T
    }

    private func convertSpeed(_ speed: UInt32?) -> Double? {
        guard let speedValue = speed else { return nil }
        switch speedValue {
        case UInt32(kUSBDeviceSpeedLow):
            return 1.5

        case UInt32(kUSBDeviceSpeedFull):
            return 12.0

        case UInt32(kUSBDeviceSpeedHigh):
            return 480.0

        case UInt32(kUSBDeviceSpeedSuper):
            return 5000.0

        case UInt32(kUSBDeviceSpeedSuperPlus):
            return 10000.0

        default:
            return nil
        }
    }
}
