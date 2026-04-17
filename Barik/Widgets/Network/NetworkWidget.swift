import SwiftUI

/// Widget for the menu, displaying Wi‑Fi and Ethernet icons.
struct NetworkWidget: View {
    @ObservedObject private var viewModel = NetworkStatusService.shared

    static func wifiSymbolName(for state: NetworkState, ssid: String) -> String {
        switch state {
        case .connected, .connecting:
            return "wifi"
        case .connectedWithoutInternet:
            return "wifi.exclamationmark"
        case .disconnected, .disabled:
            return "wifi.slash"
        case .notSupported:
            return "wifi.exclamationmark"
        }
    }

    var body: some View {
        HStack(spacing: 15) {
            if viewModel.wifiState != .notSupported {
                wifiIcon
            }
            if viewModel.ethernetState != .notSupported {
                ethernetIcon
            }
        }
        .font(.system(size: 15))
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
    }

    private var wifiIcon: some View {
        switch viewModel.wifiState {
        case .connected:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.foregroundOutside)
        case .connecting:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.yellow)
        case .connectedWithoutInternet:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.gray)
        case .disabled:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.red)
        case .notSupported:
            return Image(systemName: Self.wifiSymbolName(for: viewModel.wifiState, ssid: viewModel.ssid))
                .foregroundColor(.gray)
        }
    }

    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            return Image(systemName: "network")
                .foregroundColor(.primary)
        case .connectedWithoutInternet:
            return Image(systemName: "network")
                .foregroundColor(.yellow)
        case .connecting:
            return Image(systemName: "network.slash")
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "network.slash")
                .foregroundColor(.red)
        case .disabled, .notSupported:
            return Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }
}

struct NetworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        NetworkWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
