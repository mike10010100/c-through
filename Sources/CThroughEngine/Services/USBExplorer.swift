import Foundation
import IOKit
import IOKit.usb

public protocol USBExplorerProtocol {
    func fetchTopology() -> [USBDevice]
    func startMonitoring(onChange: @escaping () -> Void)
    func stopMonitoring()
}

public class USBExplorer: USBExplorerProtocol {
    private var notifyPort: IONotificationPortRef?
    private var addIterator: io_iterator_t = 0
    private var removeIterator: io_iterator_t = 0
    private var onChangeCallback: (() -> Void)?

    public init() {}

    public func fetchTopology() -> [USBDevice] {
        var devicesMap: [UInt64: USBDevice] = [:]
        var parentMap: [UInt64: UInt64] = [:]
        var childrenMap: [UInt64: [UInt64]] = [:]

        var iterator: io_iterator_t = 0
        // Search for both IOUSBDevice and IOUSBHostDevice for maximum coverage
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let result = IOServiceGetMatchingServices(0, matchingDict, &iterator)

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
                    if IOObjectConformsTo(parent, kIOUSBDeviceClassName) != 0 || 
                       IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 {
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
                if parentID != 0 {
                    childrenMap[parentID, default: []].append(id)
                }
            }

            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }

        // Recursive assembly to avoid struct-copy issues
        func assemble(deviceID: UInt64) -> USBDevice? {
            guard var usbDevice = devicesMap[deviceID] else { return nil }
            let childIDs = childrenMap[deviceID] ?? []
            usbDevice.children = childIDs.compactMap { assemble(deviceID: $0) }
            return usbDevice
        }

        let roots = devicesMap.keys.filter { id in
            let pID = parentMap[id] ?? 0
            return pID == 0 || devicesMap[pID] == nil
        }.compactMap { assemble(deviceID: $0) }

        return roots
    }

    public func startMonitoring(onChange: @escaping () -> Void) {
        self.onChangeCallback = onChange
        
        notifyPort = IONotificationPortCreate(0)
        guard let notifyPort = notifyPort else { return }
        
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        
        // Notification for device arrival
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOPublishNotification,
            matchingDict,
            { userData, iterator in
                let explorer = Unmanaged<USBExplorer>.fromOpaque(userData!).takeUnretainedValue()
                while IOIteratorNext(iterator) != 0 {} // Must consume iterator
                explorer.onChangeCallback?()
            },
            selfPtr,
            &addIterator
        )
        
        // Notification for device removal
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOTerminatedNotification,
            matchingDict,
            { userData, iterator in
                let explorer = Unmanaged<USBExplorer>.fromOpaque(userData!).takeUnretainedValue()
                while IOIteratorNext(iterator) != 0 {} // Must consume iterator
                explorer.onChangeCallback?()
            },
            selfPtr,
            &removeIterator
        )
        
        // Initial consumption
        while IOIteratorNext(addIterator) != 0 {}
        while IOIteratorNext(removeIterator) != 0 {}
    }

    public func stopMonitoring() {
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if addIterator != 0 {
            IOObjectRelease(addIterator)
            addIterator = 0
        }
        if removeIterator != 0 {
            IOObjectRelease(removeIterator)
            removeIterator = 0
        }
    }

    private func buildDevice(from service: io_service_t, id: UInt64) -> USBDevice? {
        let name = getProperty(service, kUSBProductString as String) as String? ?? "Unknown Device"
        let manufacturer = getProperty(service, kUSBVendorString as String) as String?
        let vendorID = getProperty(service, kUSBVendorID as String) as UInt16?
        let productID = getProperty(service, kUSBProductID as String) as UInt16?
        let serialNumber = getProperty(service, kUSBSerialNumberString as String) as String?
        let speed = getProperty(service, "Device Speed") as UInt32?

        let speedMbps = convertSpeed(speed)
        let maxSpeedMbps = getMaxCapability(from: service)
        let isThunderbolt = name.lowercased().contains("thunderbolt") || speed == 6

        return USBDevice(
            id: String(id),
            name: name,
            manufacturer: manufacturer,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            negotiatedSpeedMbps: speedMbps,
            maxCapableSpeedMbps: maxSpeedMbps,
            isThunderbolt: isThunderbolt,
            children: []
        )
    }

    private func getMaxCapability(from service: io_service_t) -> Double? {
        // More sophisticated capability detection
        // If we see a SuperSpeed device, it's at least 5Gbps.
        // If it's SuperSpeedPlus, it's at least 10Gbps.
        // We can also check for "USB4" or "Thunderbolt" in the name or properties.
        
        if let speed = getProperty(service, "Device Speed") as UInt32? {
            if speed >= UInt32(kUSBDeviceSpeedSuperPlus) {
                return 10000.0
            } else if speed >= UInt32(kUSBDeviceSpeedSuper) {
                return 5000.0
            }
        }
        
        // Default to assuming 10Gbps for modern SSDs to trigger the red line if they fall to 480Mbps
        let name = (getProperty(service, kUSBProductString as String) as String? ?? "").lowercased()
        if name.contains("ssd") || name.contains("nvme") || name.contains("t7") || name.contains("t9") {
            return 10000.0
        }
        
        return nil
    }

    private func getProperty<T>(_ service: io_service_t, _ key: String) -> T? {
        let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        guard let value = property?.takeRetainedValue() else { return nil }
        
        // Handle CFNumber to T (Int, UInt16, UInt32, etc)
        if let number = value as? NSNumber {
            if T.self == UInt16.self {
                return number.uint16Value as? T
            } else if T.self == UInt32.self {
                return number.uint32Value as? T
            } else if T.self == Int.self {
                return number.intValue as? T
            }
        }
        
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
        case 5:
            return 20000.0 // Some controllers use 5 for Gen2x2
        case 6:
            return 40000.0 // USB4 / Thunderbolt
        default:
            return nil
        }
    }
}

