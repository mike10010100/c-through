import AppKit
import SwiftUI

private class CanvasHostingView<Content: View>: NSHostingView<Content> {}

private class CanvasScrollView: NSScrollView {
    // Explicitly allow magnification to ensure pinch gestures work.
    override func magnify(with event: NSEvent) {
        if allowsMagnification {
            // Let the super handle it, which is the most robust way on macOS.
            super.magnify(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && allowsMagnification {
            let dy = event.scrollingDeltaY
            if dy != 0 {
                let magDelta = dy * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
                let newMag = max(minMagnification, min(maxMagnification, magnification + magDelta))
                let pointInView = contentView.convert(event.locationInWindow, from: nil)
                setMagnification(newMag, centeredAt: pointInView)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Native Zoomable Canvas

struct NativeZoomableCanvas<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true 
        scrollView.magnification = 1.0
        scrollView.maxMagnification = 5.0
        scrollView.minMagnification = 0.1
        scrollView.drawsBackground = false

        let hostingView = CanvasHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.documentView = hostingView

        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView

        // Click-and-drag to pan
        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.buttonMask = 0x1
        pan.delaysPrimaryMouseButtonEvents = false
        scrollView.addGestureRecognizer(pan)

        // Initial centering
        DispatchQueue.main.async {
            context.coordinator.performInitialFit()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
            
            let newSize = hostingView.fittingSize
            if newSize != .zero && hostingView.frame.size != newSize {
                hostingView.frame = CGRect(origin: .zero, size: newSize)
                
                // If this is a significant content update, ensure it's still visible
                if !context.coordinator.hasPerformedInitialFit && newSize.width > 2500 {
                    context.coordinator.performInitialFit(animated: true)
                }
            }
        }
    }

    class Coordinator: NSObject {
        fileprivate weak var scrollView: CanvasScrollView?
        fileprivate weak var hostingView: CanvasHostingView<Content>?
        fileprivate var hasPerformedInitialFit = false
        private var lastDragLocation: NSPoint = .zero

        func performInitialFit(animated: Bool = false) {
            guard let scrollView = scrollView, let hostingView = hostingView else { return }
            
            let contentSize = hostingView.fittingSize
            guard contentSize.width > 0 else { return }
            
            // Set frame if needed
            hostingView.frame = CGRect(origin: .zero, size: contentSize)
            
            let visibleSize = scrollView.contentView.bounds.size
            guard visibleSize.width > 0 && visibleSize.height > 0 else {
                // If not visible yet, retry later
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.performInitialFit(animated: animated)
                }
                return
            }
            
            // Padding used in the SwiftUI view
            let padding: CGFloat = 1000
            
            // Target the actual graph area
            let graphRect = CGRect(
                x: padding,
                y: padding,
                width: max(contentSize.width - 2 * padding, 400),
                height: max(contentSize.height - 2 * padding, 400)
            )
            
            // Calculate magnification to fit the graph area with some margin
            let targetMag = min(
                visibleSize.width / (graphRect.width + 100),
                visibleSize.height / (graphRect.height + 100)
            )
            
            let finalMag = max(scrollView.minMagnification, min(scrollView.maxMagnification, targetMag))
            let centerPoint = NSPoint(x: contentSize.width / 2, y: contentSize.height / 2)
            
            let finalClipSize = NSSize(
                width: visibleSize.width / finalMag,
                height: visibleSize.height / finalMag
            )
            let newOrigin = NSPoint(
                x: max(0, centerPoint.x - finalClipSize.width / 2.0),
                y: max(0, centerPoint.y - finalClipSize.height / 2.0)
            )
            
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    scrollView.animator().magnification = finalMag
                    scrollView.contentView.animator().setBoundsOrigin(newOrigin)
                }
            } else {
                scrollView.magnification = finalMag
                scrollView.contentView.scroll(to: newOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            
            if graphRect.width > 500 {
                hasPerformedInitialFit = true
            }
        }

        @objc
        func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let scrollView else { return }
            let location = gesture.location(in: scrollView)

            switch gesture.state {
            case .began:
                lastDragLocation = location

            case .changed:
                let delta = NSPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
                lastDragLocation = location

                let clipView = scrollView.contentView
                var origin = clipView.bounds.origin
                origin.x -= delta.x
                origin.y -= delta.y
                
                // Use NSScrollView's own bound checking
                let constrainedOrigin = clipView.constrainBoundsRect(
                    NSRect(origin: origin, size: clipView.bounds.size)
                ).origin
                
                clipView.scroll(to: constrainedOrigin)
                scrollView.reflectScrolledClipView(clipView)

            default:
                break
            }
        }
    }
}
