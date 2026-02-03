import SwiftUI

struct MenuBarPopupView<Content: View>: View {
    let content: Content
    let isPreview: Bool
    let position: BarPosition
    let onSizeChange: ((CGSize) -> Void)?

    @State private var animationValue: Double = 0.01
    @State private var isShowAnimation = false
    @State private var isHideAnimation = false

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)
    private let willChangeContent = NotificationCenter.default.publisher(
        for: .willChangeContent)

    init(
        isPreview: Bool = false,
        position: BarPosition = .top,
        onSizeChange: ((CGSize) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isPreview = isPreview
        self.position = position
        self.onSizeChange = onSizeChange
        if isPreview {
            _animationValue = State(initialValue: 1.0)
        }
    }

    private var animationAnchor: UnitPoint {
        switch position {
        case .top: .top      // Popup below bar, grows down
        case .bottom: .bottom // Popup above bar, grows up
        }
    }

    var body: some View {
        let measuredContent = content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupSizePreferenceKey.self,
                    value: proxy.size
                )
            }
        )

        ZStack(alignment: position == .top ? .top : .bottom) {
            measuredContent
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: position == .top ? .top : .bottom
        )
        .onPreferenceChange(PopupSizePreferenceKey.self) { newSize in
            guard newSize.width > 0, newSize.height > 0 else { return }
            onSizeChange?(newSize)
        }
            .background(Color.black)
            .cornerRadius(((1.0 - animationValue) * 1) + 40)
            .shadow(radius: 30)
            .blur(radius: (1.0 - (0.1 + 0.9 * animationValue)) * 20)
            .scaleEffect(x: 0.2 + 0.8 * animationValue, y: animationValue, anchor: animationAnchor)
            .opacity(animationValue)
            .transaction { transaction in
                if isHideAnimation {
                    transaction.animation = .linear(duration: 0.1)
                }
            }
            .onReceive(willShowWindow) { _ in
                isShowAnimation = true
                withAnimation(
                    .smooth(
                        duration: Double(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        ) / 1000.0, extraBounce: 0.3)
                ) {
                    animationValue = 1.0
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now()
                        + .milliseconds(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        )
                ) {
                    isShowAnimation = false
                }
            }
            .onReceive(willHideWindow) { _ in
                isHideAnimation = true
                withAnimation(
                    .interactiveSpring(
                        duration: Double(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        ) / 1000.0)
                ) {
                    animationValue = 0.01
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now()
                        + .milliseconds(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        )
                ) {
                    isHideAnimation = false
                }
            }
            .onReceive(willChangeContent) { _ in
                isHideAnimation = true
                withAnimation(
                    .spring(
                        duration: Double(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        ) / 1000.0)
                ) {
                    animationValue = 0.01
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now()
                        + .milliseconds(
                            Constants
                                .menuBarPopupAnimationDurationInMilliseconds
                        )
                ) {
                    isHideAnimation = false
                }
            }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
    }
}

private struct PopupSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension Notification.Name {
    static let willShowWindow = Notification.Name("willShowWindow")
    static let willHideWindow = Notification.Name("willHideWindow")
    static let willChangeContent = Notification.Name("willChangeContent")
}
