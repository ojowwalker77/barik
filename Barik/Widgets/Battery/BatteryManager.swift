import Combine
import Foundation
import IOKit.ps

/// This class monitors the battery status.
class BatteryManager: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var timer: Timer?
    private var powerStateObserver: NSObjectProtocol?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private let fallbackInterval: TimeInterval = 30

    init() {
        startMonitoring()
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        stopMonitoring()
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    private func startMonitoring() {
        installPowerSourceNotification()
        startFallbackTimer()
        updateBatteryStatus()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = nil
        }
    }

    private func startFallbackTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fallbackInterval, repeats: true) {
            [weak self] _ in
            self?.updateBatteryStatus()
        }
    }

    private func installPowerSourceNotification() {
        guard powerSourceRunLoopSource == nil else { return }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource(
            BatteryManager.powerSourceCallback,
            context
        )?.takeRetainedValue() {
            powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func handlePowerSourceChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateBatteryStatus()
        }
    }

    /// This method updates the battery level and charging state.
    func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?
                .takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(
                snapshot, source)?.takeUnretainedValue() as? [String: Any],
                let currentCapacity = description[
                    kIOPSCurrentCapacityKey as String] as? Int,
                let maxCapacity = description[kIOPSMaxCapacityKey as String]
                    as? Int,
                let charging = description[kIOPSIsChargingKey as String]
                    as? Bool,
                let powerSourceState = description[
                    kIOPSPowerSourceStateKey as String] as? String
            {
                let isAC = (powerSourceState == kIOPSACPowerValue)

                DispatchQueue.main.async {
                    self.batteryLevel = (currentCapacity * 100) / maxCapacity
                    self.isCharging = charging
                    self.isPluggedIn = isAC
                    self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
            }
        }
    }

    private static let powerSourceCallback: IOPSPowerSourceCallbackType = { context in
        guard let context else { return }
        let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
        manager.handlePowerSourceChange()
    }
}
