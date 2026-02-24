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

    /// The BSD name (e.g. disk4) if this device is a storage device.
    public let bsdName: String?

    /// The mount path if this device is a storage device.
    public let mountPath: String?

    /// Whether this connection is bottlenecked by the cable or port.
    public var isBottlenecked: Bool {
        guard let actual = negotiatedSpeedMbps, let max = maxCapableSpeedMbps else { return false }
        return actual < max
    }

    /// Whether this is a Thunderbolt connection.
    public let isThunderbolt: Bool

    /// Whether this device represents a mass storage volume that can be ejected.
    public var canEject: Bool {
        return bsdName != nil || mountPath != nil
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
        isThunderbolt: Bool = false,
        children: [USBDevice] = [],
        bsdName: String? = nil,
        mountPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.negotiatedSpeedMbps = negotiatedSpeedMbps
        self.maxCapableSpeedMbps = maxCapableSpeedMbps
        self.isThunderbolt = isThunderbolt
        self.children = children
        self.bsdName = bsdName
        self.mountPath = mountPath
    }

    public static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.manufacturer == rhs.manufacturer &&
               lhs.vendorID == rhs.vendorID &&
               lhs.productID == rhs.productID &&
               lhs.serialNumber == rhs.serialNumber &&
               lhs.negotiatedSpeedMbps == rhs.negotiatedSpeedMbps &&
               lhs.maxCapableSpeedMbps == rhs.maxCapableSpeedMbps &&
               lhs.isThunderbolt == rhs.isThunderbolt &&
               lhs.children == rhs.children &&
               lhs.bsdName == rhs.bsdName &&
               lhs.mountPath == rhs.mountPath
    }
}
