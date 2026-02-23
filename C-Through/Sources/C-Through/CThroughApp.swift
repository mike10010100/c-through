import CThroughEngine
import SwiftUI

@main
struct CThroughApp: App {
  @StateObject private var viewModel = DeviceViewModel(explorer: USBExplorer())

  var body: some Scene {
    WindowGroup {
      ContentView(viewModel: viewModel)
        .frame(minWidth: 800, minHeight: 600)
    }
  }
}

class DeviceViewModel: ObservableObject {
  @Published var devices: [USBDevice] = []
  private let explorer: USBExplorerProtocol

  init(explorer: USBExplorerProtocol) {
    self.explorer = explorer
    refresh()
  }

  func refresh() {
    devices = explorer.fetchTopology()
  }
}

struct ContentView: View {
  @ObservedObject var viewModel: DeviceViewModel

  var body: some View {
    NavigationStack {
      List(viewModel.devices) { device in
        DeviceCardView(device: device)
          .listRowSeparator(.hidden)
      }
      .navigationTitle("C-Through")
      .toolbar {
        Button("Refresh") {
          viewModel.refresh()
        }
      }
    }
  }
}

struct DeviceCardView: View {
  let device: USBDevice

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(device.name)
          .font(.headline)
        if let mfr = device.manufacturer {
          Text(mfr)
            .font(.caption)
        }
      }
      Spacer()
      if let speed = device.negotiatedSpeedMbps {
        VStack(alignment: .trailing) {
          Text("\(Int(speed)) Mbps")
            .foregroundColor(device.isBottlenecked ? .red : .primary)
          if device.isBottlenecked {
            Text("Limited by cable")
              .font(.caption2)
              .foregroundColor(.red)
          }
        }
      }
    }
    .padding()
    .background(Color(.windowBackgroundColor))
    .cornerRadius(10)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(device.isBottlenecked ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
    )
  }
}
