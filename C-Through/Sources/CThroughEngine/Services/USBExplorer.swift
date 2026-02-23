import Foundation
import IOKit
import IOKit.usb
public protocol USBExplorerProtocol {
  func fetchTopology() -> [USBDevice]
}

public class USBExplorer: USBExplorerProtocol {
  public init() {}

  public func fetchTopology() -> [USBDevice] {
    var devices: [USBDevice] = []
    var iterator: io_iterator_t = 0

    let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

    guard result == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
      if let device = buildDevice(from: service) {
        // In IOKit, all USB devices are flat in this matching iterator.
        // We need to build the tree manually by finding parents/children
        // OR we can start from the Root of the IORegistry.
        // For now, let's keep it flat or use IORegistryEntryGetChildIterator.
        devices.append(device)
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }

    return devices
  }

  private func buildDevice(from service: io_service_t) -> USBDevice? {
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
      id: "\(vendorID ?? 0):\(productID ?? 0):\(serialNumber ?? UUID().uuidString)",
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
    case UInt32(kUSBDeviceSpeedLow): return 1.5
    case UInt32(kUSBDeviceSpeedFull): return 12.0
    case UInt32(kUSBDeviceSpeedHigh): return 480.0
    case UInt32(kUSBDeviceSpeedSuper): return 5000.0
    case UInt32(kUSBDeviceSpeedSuperPlus): return 10000.0
    default: return nil
    }
  }
}
