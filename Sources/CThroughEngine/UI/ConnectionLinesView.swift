import SwiftUI

struct ConnectionLinesView: View {
    let anchors: [DeviceAnchorData]
    let devices: [USBDevice]
    let proxy: GeometryProxy

    var body: some View {
        Canvas { context, _ in
            drawLines(for: devices, to: "HOST", in: &context)
        }
        .allowsHitTesting(false)
    }

    private func drawLines(for devices: [USBDevice], to parentID: String, in context: inout GraphicsContext) {
        guard let parentAnchorData = anchors.first(where: { $0.id == parentID }) else { return }

        let p2Rect = proxy[parentAnchorData.bounds]
        let p2 = CGPoint(x: p2Rect.minX, y: p2Rect.midY) // Leading edge of parent

        for device in devices {
            if let deviceAnchorData = anchors.first(where: { $0.id == device.id }) {
                let p1Rect = proxy[deviceAnchorData.bounds]
                let p1 = CGPoint(x: p1Rect.maxX, y: p1Rect.midY) // Trailing edge of child

                var path = Path()
                path.move(to: p1)

                // Smooth organic curve
                let diff = p2.x - p1.x
                let control1 = CGPoint(x: p1.x + diff * 0.4, y: p1.y)
                let control2 = CGPoint(x: p1.x + diff * 0.6, y: p2.y)
                path.addCurve(to: p2, control1: control1, control2: control2)

                let color = device.isBottlenecked ? Color.red : Color.gray.opacity(0.4)
                let thickness = lineThickness(for: device.negotiatedSpeedMbps)

                context.stroke(path, with: .color(color), lineWidth: thickness)

                // Thunderbolt indicator (placed near the host/parent side of the cable)
                if device.isThunderbolt {
                    let iconPoint = CGPoint(x: p1.x + (p2.x - p1.x) * 0.8, y: p2.y)
                    context.draw(Image(systemName: "bolt.fill"), at: iconPoint, anchor: .center)
                }

                drawLines(for: device.children, to: device.id, in: &context)
            }
        }
    }

    private func lineThickness(for speed: Double?) -> CGFloat {
        let mbps = speed ?? 480.0
        if mbps <= 12.0 { return 1.5 }
        if mbps <= 480.0 { return 3.0 }
        if mbps <= 5000.0 { return 5.0 }
        if mbps <= 10000.0 { return 7.0 }
        return 10.0
    }
}
