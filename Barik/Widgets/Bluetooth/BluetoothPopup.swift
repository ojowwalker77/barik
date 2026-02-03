import SwiftUI

struct BluetoothPopup: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    let device: BluetoothDevice

    var body: some View {
        VStack(spacing: 16) {
            // Device icon
            Image(systemName: "headphones")
                .font(.system(size: 32))
                .foregroundStyle(.white)

            // Device name
            Text(device.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button(action: openSoundSettings) {
                Text("Sound Settings...")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text("Bluetooth Output")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if bluetoothManager.bluetoothOutputDevices.isEmpty {
                    Text("No Bluetooth devices found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(bluetoothManager.bluetoothOutputDevices, id: \.deviceID) { output in
                        Button {
                            bluetoothManager.setDefaultOutputDevice(deviceID: output.deviceID)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 11))
                                Text(output.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                if output.deviceID == bluetoothManager.currentOutputDeviceID {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 220)
    }

    private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct BluetoothPopup_Previews: PreviewProvider {
    static var previews: some View {
        BluetoothPopup(device: BluetoothDevice(name: "AirPods Pro", deviceID: 0))
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
