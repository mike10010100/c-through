# Product Requirements Document: C-Through (macOS)

## 1. Executive Summary
**C-Through** is a native macOS utility that visualizes the complex topology of connected USB and Thunderbolt devices. By translating raw IOKit system data into a high-fidelity, interactive node-link diagram, it allows users to instantly understand how their peripherals are connected, what speeds they are negotiating, and—crucially—identify performance bottlenecks caused by inadequate cables or hubs.

## 2. Target Audience
*   **Creative Professionals:** Video editors, musicians, and photographers managing high-speed external storage arrays, displays, and audio interfaces.
*   **Hardware Enthusiasts & "Desk Setup" Builders:** Users managing complex docks, multiple hubs, and numerous peripherals who need to optimize their setups.
*   **Developers & IT Support:** Professionals needing a quick, visual overview of the hardware tree for debugging.

## 3. User Needs & Problem Statement
The USB-C ecosystem is notoriously confusing. Cables and ports share the same physical connector but support vastly different protocols and speeds (from USB 2.0's 480 Mbps to Thunderbolt 4's 40 Gbps). Users frequently experience "silent bottlenecks"—where a 10 Gbps SSD operates at 480 Mbps because of a cheap charging cable—with no intuitive way to diagnose the issue in macOS.

## 4. Functional Requirements

### 4.1. Visual Topology Map (The Core View)
The primary interface is a canvas displaying a hierarchical graph, flowing right-to-left (Host on the right, devices on the left).

*   **The Host Node:** A prominent visual representation of the user's Mac (e.g., a MacBook Pro graphic) serving as the root of the tree.
*   **Device Nodes (Cards):**
    *   Styling: Light gray rounded rectangles with Apple's standard corner radii.
    *   Icon: A blue rounded square containing a category-specific icon (Keyboard, Mouse, Storage, Display, Hub).
    *   Text: Primary Device Name (e.g., "PSSD T9 • 4 TB") and Secondary Manufacturer Name (e.g., "Samsung").
    *   Interaction: Hub nodes must have expand/collapse toggles to manage complex, deeply nested trees.
*   **Connection Edges ("Cables"):**
    *   **Thickness as Bandwidth:** The stroke width of the line connecting nodes must proportionally represent the *actual negotiated* link speed (e.g., thicker for 40 Gbps, very thin for 12 Mbps).
    *   **Speed Labels:** The numerical speed (e.g., "480", "10,000") is displayed inline near the destination node.
    *   **Protocol Indicators:** Special connections (like Thunderbolt) should feature an inline icon (e.g., a lightning bolt) on the cable line near the host.

### 4.2. Bottleneck Detection ("The Red Line" Feature)
*   **Logic:** The application must parse the device's SuperSpeed Capability Descriptors (via IOKit) to determine its *maximum supported speed*. It must then compare this against the *actual negotiated speed*.
*   **Visualization:** If a device is operating significantly below its capability (e.g., a SuperSpeed device on a High-Speed link), the connection edge and the speed label must be colored **Red**.
*   **Legend/Explanation:** A persistent, unobtrusive legend must explain the line thicknesses (1.5 Mbps to 40,000 Mbps) and explicitly state that a red line means "Limited by cable throughput".

### 4.3. Real-time Monitoring & Utility
*   **Live Updates:** The topology map must observe `IOKit` registry changes and update instantly upon plug/unplug events. Layout transitions must be animated smoothly to maintain user context.
*   **Eject Integration:** Provide a standard mechanism (e.g., a hover icon on the node) to safely unmount mass storage volumes associated with a specific USB node directly from the graph.

### 4.4. Inspector Panel (Detailed View)
*   Clicking a node opens a sidebar or popover with detailed technical specifications:
    *   Vendor ID (VID) and Product ID (PID).
    *   Serial Number.
    *   Reported USB Specification version (parsed from the `bcdUSB` field).
    *   Power requirements (Current drawn vs. available bus power).

## 5. Non-Functional Requirements
*   **Design Language:** Strict adherence to modern macOS aesthetics. The app should feel like an official Apple utility, utilizing SwiftUI, `SF Symbols`, and standard materials (translucency).
*   **Performance:** The app must have a minimal CPU/Memory footprint. It should observe the IOKit registry asynchronously to prevent blocking the main thread during device enumeration.
*   **Permissions:** The app should operate entirely within standard user-level permissions without requiring a `kext` (kernel extension) or elevated privileges.

## 6. Technical Architecture & Implementation Strategy

*   **Frontend (UI/UX):** **Swift and SwiftUI**. 
    *   For the topology map, we will use a custom layout engine built on top of SwiftUI `Canvas` or custom layout protocols to handle the specific right-to-left tree layout with orthogonal or bezier edge routing.
*   **Backend (Hardware Data Engine):** **Native Swift + IOKit**.
    *   *Device Discovery:* Use `IOServiceMatching(kIOUSBDeviceClassName)` to discover devices and `IORegistryEntryGetChildIterator` to map the hierarchical topology (Hub -> Port -> Device).
    *   *Speed Analysis:* 
        *   **Negotiated Speed:** Read directly using `IOUSBDeviceInterface::GetDeviceSpeed`.
        *   **Max Capability:** Read the device configuration descriptors (`GetConfigurationDescriptorPtr`) and parse the `SuperSpeed Device Capability` (bDevCapabilityType = 3) to determine what the hardware is actually capable of, enabling the "Red Line" bottleneck detection.
    *   *Rationale:* A purely native approach eliminates the overhead, app size, and IPC complexity of bundling a separate binary (like Rust's `cyme`), while providing deeper integration with macOS memory management and event loops.

## 7. Future Considerations
*   **Photorealistic Icon Library:** Allow users to map specific VID/PIDs to high-resolution, 3D-style icons of the actual hardware (similar to how macOS displays native accessories).
*   **Power Delivery (PD) Visualization:** Expand the IOKit implementation to read USB-C PD controllers (if accessible without private APIs) to visualize wattage flow and charging bottlenecks.
