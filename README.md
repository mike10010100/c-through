# C-Through

[![Build & Release](https://github.com/mike10010100/pretty-usb-ls/actions/workflows/build-release.yml/badge.svg)](https://github.com/mike10010100/pretty-usb-ls/actions/workflows/build-release.yml)

**C-Through** is a native macOS utility designed to visualize your USB and Thunderbolt device topology and identify performance bottlenecks (the "USB-C mess").

## Features
- **Visual Topology Map**: A high-fidelity, hierarchical view of all connected USB/Thunderbolt devices.
- **Bottleneck Detection**: Automatically identifies when a device is connected via an inadequate cable or port (e.g., a 10Gbps SSD running at 480Mbps).
- **Infinite Canvas Navigation**: Native macOS zoom and pan experience with no obtrusive scrollbars.
- **Organic Connection Lines**: Beautiful cubic bezier "cables" that connect devices to hubs and the host.
- **Real-time Monitoring**: Reacts instantly to plug/unplug events.
- **Automated Verification**: Uses snapshot testing to ensure UI consistency and layout correctness.

## Navigation & Controls
- **Panning**: Click and drag anywhere on the canvas, or use standard mouse-wheel/trackpad scrolling.
- **Zooming**: 
  - **Trackpad**: Pinch-to-zoom.
  - **Mouse**: `Command` + Scroll Wheel.
- **Refresh**: `Command + R` or use the floating refresh button in the top-right.

## Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later (for Swift 5.9+ support)

### Building and Running
```bash
swift build
swift run
```

### Running Tests (including UI Snapshots)
```bash
swift test --enable-code-coverage
```
*Note: Snapshot tests generate PNG files in the project root for visual verification.*

### Quality Checks
```bash
swiftlint
```

## Documentation
- [Product Requirements Document (PRD)](PRD.md)
- [Agent Coordination (AGENTS.md)](AGENTS.md)

## Project Structure
- `Sources/CThroughEngine`: Core logic for IOKit discovery and the `Views` library.
- `Sources/C-Through`: Main application entry point.
- `Tests`: Comprehensive XCTest suite.
