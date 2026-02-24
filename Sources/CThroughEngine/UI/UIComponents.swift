import SwiftUI

enum UIConstants {
    static let cardWidth: CGFloat = 280
    static let cardHeight: CGFloat = 70
    static let sidebarWidth: CGFloat = 320
}

func iconFor(_ device: USBDevice) -> String {
    let name = device.name.lowercased()
    if name.contains("hub") { return "cable.connector" }
    if name.contains("ssd") || name.contains("drive") || name.contains("external") { return "externaldrive.fill" }
    if name.contains("keyboard") { return "keyboard.fill" }
    if name.contains("mouse") || name.contains("trackpad") || name.contains("receiver") { return "mouse.fill" }
    if name.contains("display") || name.contains("monitor") { return "desktopcomputer" }
    if name.contains("camera") || name.contains("brio") || name.contains("video") { return "camera.fill" }
    if name.contains("mic") || name.contains("yeti") || name.contains("audio") { return "mic.fill" }
    return "usb.fill"
}

func formatSpeed(_ mbps: Double?) -> String {
    guard let mbps = mbps else { return "Unknown" }
    if mbps >= 1000 {
        return String(format: "%.1f Gbps", mbps / 1000.0)
    }
    return "\(Int(mbps)) Mbps"
}
