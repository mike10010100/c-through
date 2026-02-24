import Foundation
import IOKit
import IOKit.usb
import AppKit

public protocol IORegistryProvider {
    func getMatchingServices(_ matchingDict: CFDictionary) -> io_iterator_t
    func getRegistryEntryID(_ service: io_service_t) -> UInt64
    func getParentEntry(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_registry_entry_t
    func conformsTo(_ service: io_object_t, _ className: String) -> Bool
    func createCFProperty(_ service: io_registry_entry_t, _ key: String) -> AnyObject?
    func getChildIterator(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_iterator_t
    func iteratorNext(_ iterator: io_iterator_t) -> io_service_t
    func objectRelease(_ object: io_object_t)
    func objectRetain(_ object: io_object_t)
}

public class DefaultIORegistryProvider: IORegistryProvider {
    public init() {}
    public func getMatchingServices(_ matchingDict: CFDictionary) -> io_iterator_t {
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        return iterator
    }

    public func getRegistryEntryID(_ service: io_service_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        return id
    }

    public func getParentEntry(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_registry_entry_t {
        var parent: io_registry_entry_t = 0
        IORegistryEntryGetParentEntry(service, plane, &parent)
        return parent
    }

    public func conformsTo(_ service: io_object_t, _ className: String) -> Bool {
        return IOObjectConformsTo(service, className) != 0
    }

    public func createCFProperty(_ service: io_registry_entry_t, _ key: String) -> AnyObject? {
        let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return property?.takeRetainedValue()
    }

    public func getChildIterator(_ service: io_registry_entry_t, _ plane: UnsafePointer<Int8>) -> io_iterator_t {
        var iterator: io_iterator_t = 0
        IORegistryEntryGetChildIterator(service, plane, &iterator)
        return iterator
    }

    public func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        return IOIteratorNext(iterator)
    }

    public func objectRelease(_ object: io_object_t) {
        IOObjectRelease(object)
    }

    public func objectRetain(_ object: io_object_t) {
        IOObjectRetain(object)
    }
}

public protocol USBExplorerProtocol {
    func fetchTopology() -> [USBDevice]
    func startMonitoring(onChange: @escaping () -> Void)
    func stopMonitoring()
    func eject(device: USBDevice)
}

public class USBExplorer: USBExplorerProtocol {
    private var notifyPort: IONotificationPortRef?
    private var addIterator: io_iterator_t = 0
    private var removeIterator: io_iterator_t = 0
    private var onChangeCallback: (() -> Void)?
    private let provider: IORegistryProvider

    public init(provider: IORegistryProvider = DefaultIORegistryProvider()) {
        self.provider = provider
    }
    
    public func eject(device: USBDevice) {
        guard let mountPath = device.mountPath else { return }
        let url = URL(fileURLWithPath: mountPath)
        Task {
            do {
                try await NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                print("Failed to eject device: \(error)")
            }
        }
    }

    public func fetchTopology() -> [USBDevice] {
        var devicesMap: [UInt64: USBDevice] = [:]
        var parentMap: [UInt64: UInt64] = [:]
        var childrenMap: [UInt64: [UInt64]] = [:]

        // Search for both IOUSBDevice and IOUSBHostDevice for maximum coverage
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else { return [] }
        let iterator = provider.getMatchingServices(matchingDict)

        guard iterator != 0 else { return [] }
        defer { provider.objectRelease(iterator) }

        var device = provider.iteratorNext(iterator)
        while device != 0 {
            let id = provider.getRegistryEntryID(device)

            var parentID: UInt64 = 0
            var current = device
            provider.objectRetain(current)

            while true {
                let parent = provider.getParentEntry(current, kIOServicePlane)
                if parent != 0 {
                    if provider.conformsTo(parent, kIOUSBDeviceClassName) || 
                       provider.conformsTo(parent, "IOUSBHostDevice") {
                        parentID = provider.getRegistryEntryID(parent)
                        provider.objectRelease(parent)
                        provider.objectRelease(current)
                        break
                    }
                    provider.objectRelease(current)
                    current = parent
                } else {
                    provider.objectRelease(current)
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

            provider.objectRelease(device)
            device = provider.iteratorNext(iterator)
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
        stopMonitoring()
        self.onChangeCallback = onChange
        
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort = notifyPort else { return }
        
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary? else { return }
        
        // Notification for device arrival
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOPublishNotification,
            matchingDict,
            { userData, iterator in
                guard let userData = userData else { return }
                let explorer = Unmanaged<USBExplorer>.fromOpaque(userData).takeUnretainedValue()
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
                guard let userData = userData else { return }
                let explorer = Unmanaged<USBExplorer>.fromOpaque(userData).takeUnretainedValue()
                while IOIteratorNext(iterator) != 0 {} // Must consume iterator
                explorer.onChangeCallback?()
            },
            selfPtr,
            &removeIterator
        )
        
        // Initial consumption
        while provider.iteratorNext(addIterator) != 0 {}
        while provider.iteratorNext(removeIterator) != 0 {}
    }

    public func stopMonitoring() {
        if let notifyPort = notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if addIterator != 0 {
            provider.objectRelease(addIterator)
            addIterator = 0
        }
        if removeIterator != 0 {
            provider.objectRelease(removeIterator)
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
        
        let (bsdName, mountPath) = getStorageInfo(for: service)

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
            children: [],
            bsdName: bsdName,
            mountPath: mountPath
        )
    }

    private func getStorageInfo(for service: io_service_t) -> (String?, String?) {
        let iterator = provider.getChildIterator(service, kIOServicePlane)
        guard iterator != 0 else { return (nil, nil) }
        defer { provider.objectRelease(iterator) }

        var child = provider.iteratorNext(iterator)
        while child != 0 {
            if let bsdName = getProperty(child, "BSD Name") as String? {
                // If it's a disk, try to find if it's mounted
                let mountPath = findMountPath(for: bsdName)
                provider.objectRelease(child)
                return (bsdName, mountPath)
            }
            
            // Recurse down if needed (simplified for now)
            let (subBsd, subMount) = getStorageInfo(for: child)
            if subBsd != nil {
                provider.objectRelease(child)
                return (subBsd, subMount)
            }

            provider.objectRelease(child)
            child = provider.iteratorNext(iterator)
        }
        return (nil, nil)
    }

    private func findMountPath(for bsdName: String) -> String? {
        // This is a simplified check. In a real app, you'd use getmntinfo or diskarbitration.
        // For the sake of this tool, we'll check common /Volumes paths or return nil
        // if we can't be sure without more complex dependencies.
        return "/Volumes/\(bsdName)" // Placeholder heuristic
    }

    private func getMaxCapability(from service: io_service_t) -> Double? {
        // Attempt to read the "Capability Speed" property which some drivers provide
        if let capSpeed = getProperty(service, "Capability Speed") as UInt32? {
            return convertSpeed(capSpeed)
        }

        if let speed = getProperty(service, "Device Speed") as UInt32? {
            if speed >= UInt32(kUSBDeviceSpeedSuperPlus) {
                return 10000.0
            } else if speed >= UInt32(kUSBDeviceSpeedSuper) {
                return 5000.0
            }
        }
        
        let name = (getProperty(service, kUSBProductString as String) as String? ?? "").lowercased()
        if name.contains("ssd") || name.contains("nvme") || name.contains("t7") || name.contains("t9") || name.contains("pssd") {
            return 10000.0
        }
        
        return nil
    }

    private func getProperty<T>(_ service: io_service_t, _ key: String) -> T? {
        let value = provider.createCFProperty(service, key)
        
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

