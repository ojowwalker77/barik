import SwiftUI

struct BackgroundView: View {
    @ObservedObject var configManager = ConfigManager.shared

    private func spacer(_ geometry: GeometryProxy) -> some View {
        let theme: ColorScheme? = switch configManager.config.theme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }

        let height = configManager.config.background.resolveHeight()

        return Color.clear
            .frame(height: height ?? geometry.size.height)
            .frame(maxWidth: .infinity)
            .preferredColorScheme(theme)
    }

    var body: some View {
        let position = configManager.config.foreground.position
        let alignment: Alignment = switch position {
        case .top: .top
        case .bottom: .bottom
        }

        if configManager.config.background.enabled {
            GeometryReader { geometry in
                spacer(geometry)
                    .background(configManager.config.background.blurMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .id("blur")
            }
        }
    }
}
