import CThroughEngine
import SwiftUI

@main
struct CThroughApp: App {
    @StateObject private var viewModel = DeviceViewModel(explorer: USBExplorer())
    @State private var zoomLevel: CGFloat = 1.0

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1200, minHeight: 900)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh") { viewModel.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Zoom In") { /* Handled by NSScrollView */ }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") {}
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") {}
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
