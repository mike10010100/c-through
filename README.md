# C-Through

**C-Through** is a native macOS utility designed to visualize your USB and Thunderbolt device topology and identify performance bottlenecks (the "USB-C mess").

## Features
- **Visual Topology Map**: A hierarchical view of all connected USB/Thunderbolt devices.
- **Bottleneck Detection**: Automatically identifies when a device is connected via an inadequate cable or port (e.g., a 10Gbps SSD running at 480Mbps).
- **Real-time Monitoring**: Reacts instantly to plug/unplug events.
- **Native Performance**: Built with Swift, SwiftUI, and IOKit for a seamless macOS experience.

## Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later (for Swift 5.9+ support)

### Building from Command Line
```bash
cd C-Through
swift build
```

### Running Tests
```bash
cd C-Through
swift test --enable-code-coverage
```

### Running Linting
```bash
cd C-Through
swiftlint
```

## Documentation
- [Product Requirements Document (PRD)](PRD.md)
- [Agent Coordination (AGENTS.md)](AGENTS.md)

## Project Structure
- `C-Through/Sources/CThroughEngine`: Core logic for IOKit device enumeration and bottleneck analysis.
- `C-Through/Sources/C-Through`: SwiftUI application layer.
- `C-Through/Tests`: XCTest suite for the engine and models.
