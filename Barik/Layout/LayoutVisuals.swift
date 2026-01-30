import SwiftUI

// MARK: - Remove Preview Ghost

/// Shows a fading ghost when widget is being dragged outside for removal
struct RemovePreviewGhost: View {
    let widgetId: String

    @State private var opacity: Double = 0.6
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Group {
            if let def = WidgetRegistry.widget(for: widgetId) {
                HStack(spacing: 6) {
                    Image(systemName: def.icon)
                        .font(.system(size: 14))
                    Text(def.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.3))
                .foregroundStyle(.white)
                .cornerRadius(8)
            }
        }
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                opacity = 0.3
                scale = 0.9
            }
        }
    }
}
