import SwiftUI

struct BluetoothWidget: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var rect: CGRect = CGRect()

    /// When true, show the widget even if no device is connected (for customization mode)
    var forceShow: Bool = false

    var body: some View {
        Group {
            if let device = bluetoothManager.activeBluetoothAudio {
                // Active device - show full widget
                HStack(spacing: 4) {
                    Image(systemName: "headphones")
                        .font(.system(size: 12))

                    Text(device.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.foregroundOutside)
                .experimentalConfiguration(cornerRadius: 15)
                .frame(maxHeight: .infinity)
                .background(.black.opacity(0.001))
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                rect = geometry.frame(in: .global)
                            }
                            .onChange(of: geometry.frame(in: .global)) { _, newState in
                                rect = newState
                            }
                    }
                )
                .onTapGesture {
                    MenuBarPopup.show(rect: rect, id: "bluetooth") {
                        BluetoothPopup(device: device)
                    }
                }
            } else if forceShow {
                // No device but forced to show (customization mode) - show placeholder
                HStack(spacing: 4) {
                    Image(systemName: "headphones")
                        .font(.system(size: 12))
                    Text("Bluetooth")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }
}

struct BluetoothWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            BluetoothWidget()
        }
        .frame(width: 200, height: 100)
        .background(.yellow)
    }
}
