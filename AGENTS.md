# AGENTS.md

This file provides coordination guidance for AI agents working on the **C-Through** project. It outlines the project's technical philosophy, key constraints, and critical UI architecture.

## Project Vision
**C-Through** aims to be a high-fidelity, native macOS utility for debugging USB-C and Thunderbolt topology. It prioritizes clarity and "see-through" transparency into hardware link speeds.

## Technical Philosophy
1.  **Native First**: Prefer Swift and Apple's **IOKit** framework. Avoid non-native dependencies.
2.  **Native Interaction**: The canvas MUST feel like a native macOS creative tool (Freeform/Figma). Use `NSScrollView` wrappers where SwiftUI's standard `ScrollView` fails to provide native magnification or momentum.
3.  **Visual Verification**: GUI changes should be verified using the automated snapshot testing suite (`UISnapshotTests.swift`) to prevent "blind" development.
4.  **Test-Driven Development**: Maintain >90% code coverage in the `CThroughEngine`.

## Key Files & Modules
- `Sources/CThroughEngine/Services/USBExplorer.swift`: The IOKit implementation. Uses registry entry IDs to map parents to children accurately.
- `Sources/CThroughEngine/UI/Views.swift`: The unified UI library. 
  - `NSZoomableScrollView`: Wraps `NSScrollView` to enable pinch-to-zoom and Command-Scroll magnification.
  - `ConnectionLinesView`: Uses a `Canvas` and `AnchorPreferences` to draw lines behind nodes.
- `Tests/CThroughEngineTests/UISnapshotTests.swift`: Generates PNGs for visual inspection of the layout.

## Critical UI Constraints
- **Anchor Resolution**: Connection lines rely on `AnchorPreference` with `.bounds`. To ensure these resolve correctly, lines must be drawn in a layer that shares the same coordinate space as the nodes (usually inside the `ZStack` within the scrollable content).
- **Infinite Canvas**: The canvas uses a combination of `GeometryReader` and generous padding (`.padding(1000)`) to ensure the user can pan beyond the edges of the tree.
- **Layering**: Always draw connection lines in the `background` layer of nodes to prevent them from obscuring text or icons.

## Workflow for Agents
1.  **Research**: Use `ioreg -p IOUSB` to understand the local USB tree.
2.  **Snapshot First**: When modifying the UI, run the snapshot tests and inspect the output image before declaring the task complete.
3.  **Validate**: Always run `swift test` and `swiftlint` after any change.
4.  **Commit**: Use descriptive, conventional commit messages.
