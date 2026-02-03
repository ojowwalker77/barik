import EventKit
import SwiftUI

struct BatteryPopup: View {
    @StateObject private var batteryManager = BatteryManager()
    private var batteryConfig: ConfigData {
        ConfigManager.shared.globalWidgetConfig(for: "default.battery")
    }
    private var warningLevel: Int { batteryConfig["warning-level"]?.intValue ?? 30 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(batteryManager.batteryLevel) / 100)
                .stroke(
                    batteryColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
                .animation(
                    .easeOut(duration: 0.5), value: batteryManager.batteryLevel)
            Image(systemName: "laptopcomputer")
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundColor(.white)
            if batteryManager.isPluggedIn {
                Image(
                    systemName: batteryManager.isCharging
                        ? "bolt.fill" : "powerplug.portrait.fill"
                )
                .foregroundColor(.white)
                .offset(y: -30)
                .shadow(color: Color.black, radius: 2, x: 0, y: 0)
                .shadow(color: Color.black, radius: 2, x: 0, y: 0)
                .transition(.blurReplace)
            }
        }
        .frame(width: 60, height: 60)
        .padding(30)
    }

    private var batteryColor: Color {
        if batteryManager.isCharging {
            return .green
        } else {
            if batteryManager.isLowPowerMode {
                return .yellow
            }
            if batteryManager.batteryLevel <= warningLevel {
                return .red
            }
            return .white
        }
    }
}

struct BatteryPopup_Previews: PreviewProvider {
    static var previews: some View {
        BatteryPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
