import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject var viewModel: DeviceViewModel
    @State private var cachedAnchors: [DeviceAnchorData] = []

    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                GeometryReader { proxy in
                    NativeZoomableCanvas {
                        ZStack {
                            // Invisible background to catch deselect taps
                            Color.black.opacity(0.0001)
                                .frame(
                                    minWidth: proxy.size.width,
                                    minHeight: proxy.size.height
                                )
                                .onTapGesture {
                                    withAnimation { viewModel.selectedDevice = nil }
                                }

                            HStack(alignment: .center, spacing: 200) {
                                VStack(alignment: .trailing, spacing: 80) {
                                    if viewModel.devices.isEmpty {
                                        Text("No USB devices found.").foregroundColor(.secondary)
                                    } else {
                                        ForEach(viewModel.devices) { device in
                                            DeviceTreeBranch(device: device, viewModel: viewModel)
                                        }
                                    }
                                }

                                HostMacBookNode()
                                    .anchorPreference(key: DeviceAnchorKey.self, value: .bounds) {
                                        [DeviceAnchorData(id: "HOST", bounds: $0)]
                                    }
                            }
                        }
                        .padding(1000)
                        .backgroundPreferenceValue(DeviceAnchorKey.self) { anchors in
                            GeometryReader { geo in
                                let resolvedAnchors = anchors.isEmpty ? cachedAnchors : anchors
                                ConnectionLinesView(anchors: resolvedAnchors, devices: viewModel.devices, proxy: geo)
                                    .onChange(of: anchors.isEmpty) {
                                        if !anchors.isEmpty { cachedAnchors = anchors }
                                    }
                            }
                        }
                    }
                }

                // Overlays
                VStack {
                    Spacer()
                    HStack {
                        LegendBox().padding(20)
                        Spacer()
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: { viewModel.refresh() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .padding(10)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.plain)
                        .padding(30)
                    }
                    Spacer()
                }
            }
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }

            if let selected = viewModel.selectedDevice {
                InspectorSidebar(device: selected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(width: UIConstants.sidebarWidth)
            }
        }
    }
}
