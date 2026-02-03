import Combine
import Foundation
import CoreAudio
import AudioToolbox

struct BluetoothDevice {
    let name: String
    let deviceID: AudioDeviceID
}

class BluetoothManager: ObservableObject {
    @Published var activeBluetoothAudio: BluetoothDevice?
    @Published var bluetoothOutputDevices: [BluetoothDevice] = []
    @Published var currentOutputDeviceID: AudioDeviceID = kAudioDeviceUnknown

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        updateCurrentDevice()
        setupAudioListener()
    }

    deinit {
        removeAudioListener()
    }

    private func setupAudioListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        listenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateCurrentDevice()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )
    }

    private func removeAudioListener() {
        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    func updateCurrentDevice() {
        let deviceID = getDefaultOutputDevice()
        currentOutputDeviceID = deviceID

        guard deviceID != kAudioDeviceUnknown else {
            activeBluetoothAudio = nil
            bluetoothOutputDevices = fetchBluetoothOutputDevices()
            return
        }

        let name = getDeviceName(deviceID: deviceID)
        let transportType = getDeviceTransportType(deviceID: deviceID)
        let isBluetooth = transportType == kAudioDeviceTransportTypeBluetooth ||
                          transportType == kAudioDeviceTransportTypeBluetoothLE

        if isBluetooth {
            activeBluetoothAudio = BluetoothDevice(name: name, deviceID: deviceID)
        } else {
            activeBluetoothAudio = nil
        }
        bluetoothOutputDevices = fetchBluetoothOutputDevices()
    }

    private func getDefaultOutputDevice() -> AudioDeviceID {
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = kAudioDeviceUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        return deviceID
    }

    func setDefaultOutputDevice(deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        if status == noErr {
            DispatchQueue.main.async { [weak self] in
                self?.updateCurrentDevice()
            }
        }
    }

    private func fetchBluetoothOutputDevices() -> [BluetoothDevice] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        guard sizeStatus == noErr else { return [] }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        let listStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard listStatus == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard isOutputDevice(deviceID: deviceID) else { return nil }
            let transportType = getDeviceTransportType(deviceID: deviceID)
            let isBluetooth = transportType == kAudioDeviceTransportTypeBluetooth ||
                              transportType == kAudioDeviceTransportTypeBluetoothLE
            guard isBluetooth else { return nil }
            let name = getDeviceName(deviceID: deviceID)
            return BluetoothDevice(name: name, deviceID: deviceID)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var propertySize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        guard sizeStatus == noErr else { return false }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bufferListPointer
        )
        guard status == noErr else { return false }

        let bufferList = bufferListPointer.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private func getDeviceTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyTransportType),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &transportType
        )
        return transportType
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var result: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &result
        )
        guard status == noErr, let cfString = result?.takeUnretainedValue() else {
            return "Unknown"
        }
        return cfString as String
    }
}
