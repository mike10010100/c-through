import AppKit
import SwiftUI

extension View {
    func snapshot(size: CGSize) -> NSImage? {
        let hostingView = NSHostingView(rootView: self)
        hostingView.frame = CGRect(origin: .zero, size: size)

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        bitmap.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

func saveSnapshot(_ image: NSImage, name: String) -> String? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name)
    do {
        try pngData.write(to: path)
        return path.path
    } catch {
        return nil
    }
}
