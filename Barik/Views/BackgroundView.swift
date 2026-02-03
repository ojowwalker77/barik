import SwiftUI

struct BackgroundView: View {
    @ObservedObject var configManager = ConfigManager.shared

    private func canvas(_ geometry: GeometryProxy) -> some View {
        let theme: ColorScheme? = switch configManager.config.theme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }

        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(theme)
    }

    var body: some View {
        if configManager.config.background.enabled {
            GeometryReader { geometry in
                let isBlack = configManager.config.background.mode == .black
                if isBlack {
                    canvas(geometry)
                        .background(Color.black)
                        .id("black")
                } else {
                    canvas(geometry)
                        .background(configManager.config.background.blurMaterial)
                        .id("blur")
                }
            }
        }
    }
}
