# AGENTS.md

This file provides coordination guidance for AI agents working on the **C-Through** project. It outlines the project's technical philosophy, key constraints, and workflow.

## Project Vision
**C-Through** aims to be a high-fidelity, native macOS utility for debugging USB-C and Thunderbolt topology. It prioritizes clarity and "see-through" transparency into hardware link speeds.

## Technical Philosophy
1.  **Native First**: Avoid non-native dependencies (like Rust/C++ bridges) where possible. Prefer Swift and Apple's **IOKit** framework for system data.
2.  **SwiftUI**: All UI should be built using modern SwiftUI protocols and layouts. Use a custom layout engine for the topology graph to ensure performance and flexibility.
3.  **Test-Driven Development**: Maintain >90% code coverage. All new logic in the `CThroughEngine` must be unit-tested using `XCTest`.
4.  **Hardware-Agnostic Engine**: Design the `USBExplorerProtocol` so that the engine can be tested with mock data without requiring physical hardware.
5.  **Clean Code**: Adhere strictly to the rules in `.swiftlint.yml` and `.swiftformat`.

## Key Files & Modules
- `PRD.md`: The single source of truth for features and user needs.
- `Sources/CThroughEngine/Services/USBExplorer.swift`: The IOKit implementation for device discovery.
- `Sources/CThroughEngine/Models/USBDevice.swift`: The core model representing the device tree and bottleneck logic.
- `Sources/C-Through/CThroughApp.swift`: The main SwiftUI application entry point.

## Workflow for Agents
1.  **Research**: Use `ioreg -p IOUSB` to understand the local USB tree before modifying the `USBExplorer`.
2.  **Strategy**: Propose changes based on the PRD before implementation.
3.  **Validate**: Always run `swift test` and `swiftlint` after any code change.
4.  **Commit**: Use descriptive, conventional commit messages.

## Known Challenges
- **SuperSpeed Descriptors**: Parsing the full binary descriptor for maximum capability requires careful use of `IORegistryEntryCreateCFProperty` and pointer management.
- **Topology Hierarchy**: Correctly mapping hub-to-port-to-device relationships in IOKit requires recursive traversal of the `IOService` plane.
