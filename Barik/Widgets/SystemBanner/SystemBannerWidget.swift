import AppKit
import SwiftUI

struct BannerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                configuration.isPressed ? color.opacity(0.7) : color
            )
            .clipShape(.capsule)
    }
}

struct SystemBannerWidget: View {
    let withLeftPadding: Bool
    
    @State private var showWhatsNew: Bool = false
    @ObservedObject private var diagnostics = AppDiagnostics.shared

    init(withLeftPadding: Bool = false) {
        self.withLeftPadding = withLeftPadding
    }

    var body: some View {
        HStack(spacing: 15) {
            if withLeftPadding {
                Color.clear.frame(width: 0)
            }
            if let diagnostic = diagnostics.messages.first {
                DiagnosticBannerWidget(diagnostic: diagnostic)
            }
            UpdateBannerWidget()
            if showWhatsNew {
                ChangelogBannerWidget()
            }
        }.onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowWhatsNewBanner"))) { _ in
            withAnimation {
                showWhatsNew = true
            }
        }.onReceive(NotificationCenter.default.publisher(for: Notification.Name("HideWhatsNewBanner"))) { _ in
            withAnimation {
                showWhatsNew = false
            }
        }
    }
}

struct DiagnosticBannerWidget: View {
    let diagnostic: DiagnosticMessage

    var body: some View {
        Button {
            AppDiagnostics.shared.clear(id: diagnostic.id)
        } label: {
            HStack(spacing: 6) {
                Text(diagnostic.title)
                    .fontWeight(.semibold)
                Text(diagnostic.message)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "xmark.circle.fill")
            }
        }
        .help(diagnostic.message)
        .buttonStyle(BannerButtonStyle(color: diagnostic.kind == .config ? .red.opacity(0.8) : .orange.opacity(0.8)))
    }
}

struct SystemBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        SystemBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
