import CoreWLAN
import Network
import SwiftUI

enum NetworkState: String {
    case connected = "Connected"
    case connectedWithoutInternet = "No Internet"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    case disabled = "Disabled"
    case notSupported = "Not Supported"
}

enum WifiSignalStrength: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case unknown = "Unknown"
}

final class NetworkStatusService: NSObject, ObservableObject {
    static let shared = NetworkStatusService()

    @Published var wifiState: NetworkState = .disconnected
    @Published var ethernetState: NetworkState = .disconnected
    @Published var ssid: String = "Not connected"
    @Published var rssi: Int = 0
    @Published var noise: Int = 0
    @Published var channel: String = "N/A"

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "Barik.NetworkMonitor")
    private var timer: Timer?

    var wifiSignalStrength: WifiSignalStrength {
        if ssid == "Not connected" || ssid == "No interface" {
            return .unknown
        }
        if rssi >= -50 {
            return .high
        } else if rssi >= -70 {
            return .medium
        } else {
            return .low
        }
    }

    private override init() {
        super.init()
        startNetworkMonitoring()
        startWiFiMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
        stopWiFiMonitoring()
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            DispatchQueue.main.async {
                if path.availableInterfaces.contains(where: { $0.type == .wifi }) {
                    if path.usesInterfaceType(.wifi) {
                        switch path.status {
                        case .satisfied:
                            self.wifiState = .connected
                        case .requiresConnection:
                            self.wifiState = .connecting
                        default:
                            self.wifiState = .connectedWithoutInternet
                        }
                    } else {
                        self.wifiState = .disconnected
                    }
                } else {
                    self.wifiState = .notSupported
                }

                if path.availableInterfaces.contains(where: { $0.type == .wiredEthernet }) {
                    if path.usesInterfaceType(.wiredEthernet) {
                        switch path.status {
                        case .satisfied:
                            self.ethernetState = .connected
                        case .requiresConnection:
                            self.ethernetState = .connecting
                        default:
                            self.ethernetState = .disconnected
                        }
                    } else {
                        self.ethernetState = .disconnected
                    }
                } else {
                    self.ethernetState = .notSupported
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        monitor.cancel()
    }

    private func startWiFiMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateWiFiInfo()
        }
        updateWiFiInfo()
    }

    private func stopWiFiMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateWiFiInfo() {
        let client = CWWiFiClient.shared()
        if let interface = client.interface() {
            ssid = interface.ssid() ?? "Not connected"
            rssi = interface.rssiValue()
            noise = interface.noiseMeasurement()
            if let wlanChannel = interface.wlanChannel() {
                let band: String
                switch wlanChannel.channelBand {
                case .bandUnknown:
                    band = "unknown"
                case .band2GHz:
                    band = "2GHz"
                case .band5GHz:
                    band = "5GHz"
                case .band6GHz:
                    band = "6GHz"
                @unknown default:
                    band = "unknown"
                }
                channel = "\(wlanChannel.channelNumber) (\(band))"
            } else {
                channel = "N/A"
            }
        } else {
            ssid = "No interface"
            rssi = 0
            noise = 0
            channel = "N/A"
        }
    }
}

typealias NetworkStatusViewModel = NetworkStatusService
