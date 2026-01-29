import SwiftUI

struct BluetoothPopup: View {
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
        }
        .padding(20)
        .frame(minWidth: 160)
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
