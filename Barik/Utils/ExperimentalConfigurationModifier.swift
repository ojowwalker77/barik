import SwiftUI

private struct ExperimentalConfigurationModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.foreground.resolveHeight() }
    
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        Group {
            if !configManager.config.foreground.widgetsBackground.displayed {
                content
            } else {
                content
                    .frame(height: foregroundHeight < 45 ? 30 : 38)
                    .padding(.horizontal, foregroundHeight < 45 && horizontalPadding != 15 ? 0 :
                                foregroundHeight < 30 ? 0 : horizontalPadding
                    )
                    .background(configManager.config.foreground.widgetsBackground.blurMaterial)
                    .cornerRadius(foregroundHeight < 30 ? 0 : cornerRadius)
                    .overlay(
                        foregroundHeight < 30 ? nil :
                            Capsule().stroke(Color.noActive, lineWidth: 1)
                    )
            }
        }.scaleEffect(foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
    }
}

extension View {
    func experimentalConfiguration(
        horizontalPadding: CGFloat = 15,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(ExperimentalConfigurationModifier(
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}
