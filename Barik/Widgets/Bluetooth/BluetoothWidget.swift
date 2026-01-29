import SwiftUI

struct BluetoothWidget: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var rect: CGRect = CGRect()

    var body: some View {
        Group {
            if let device = bluetoothManager.activeBluetoothAudio {
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
