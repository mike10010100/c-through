import Foundation

/// Represents a single USB device in the topology.
public struct USBDevice: Identifiable, Codable, Equatable {
  public let id: String
  public let name: String
  public let manufacturer: String?
  public let vendorID: UInt16?
  public let productID: UInt16?
  public let serialNumber: String?

  /// The actual negotiated speed in Mbps (e.g. 480, 5000, 10000, 40000)
  public let negotiatedSpeedMbps: Double?

  /// The maximum theoretical speed the device is capable of, in Mbps.
  public let maxCapableSpeedMbps: Double?

  /// Child devices connected to this device (e.g. if this is a hub).
  public var children: [USBDevice]

  /// Whether this connection is bottlenecked by the cable or port.
  public var isBottlenecked: Bool {
    guard let actual = negotiatedSpeedMbps, let max = maxCapableSpeedMbps else { return false }
    return actual < max
  }

  public init(
    id: String,
    name: String,
    manufacturer: String? = nil,
    vendorID: UInt16? = nil,
    productID: UInt16? = nil,
    serialNumber: String? = nil,
    negotiatedSpeedMbps: Double? = nil,
    maxCapableSpeedMbps: Double? = nil,
    children: [USBDevice] = []
  ) {
    self.id = id
    self.name = name
    self.manufacturer = manufacturer
    self.vendorID = vendorID
    self.productID = productID
    self.serialNumber = serialNumber
    self.negotiatedSpeedMbps = negotiatedSpeedMbps
    self.maxCapableSpeedMbps = maxCapableSpeedMbps
    self.children = children
  }

  public static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
    return lhs.id == rhs.id
  }
}
