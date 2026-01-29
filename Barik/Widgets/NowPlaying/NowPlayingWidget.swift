import SwiftUI

// MARK: - Now Playing Widget

struct NowPlayingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject var playingManager = NowPlayingManager.shared

    @State private var widgetFrame: CGRect = .zero
    @State private var animatedWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if let song = playingManager.nowPlaying, song.state == .playing {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(song: song) { measuredWidth in
                    if animatedWidth == 0 {
                        animatedWidth = measuredWidth
                    } else if animatedWidth != measuredWidth {
                        withAnimation(.easeOut(duration: 0.15)) {
                            animatedWidth = measuredWidth
                        }
                    }
                }
                .hidden()

                // Visible content with fixed animated width.
                VisibleNowPlayingContent(song: song, width: animatedWidth)
                    .onTapGesture {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup(configProvider: configProvider)
                        }
                    }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        widgetFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
    }
}

// MARK: - Now Playing Content

/// A view that composes the album art and song text into a capsule-shaped content view.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        Group {
            if foregroundHeight < 38 {
                HStack(spacing: 8) {
                    AlbumArtView(song: song)
                    SongTextView(song: song)
                }
            } else {
                HStack(spacing: 8) {
                    AlbumArtView(song: song)
                    SongTextView(song: song)
                }
                .padding(.horizontal, foregroundHeight < 45 ? 8 : 12)
                .frame(height: foregroundHeight < 45 ? 30 : 38)
                .background(configManager.config.experimental.foreground.widgetsBackground.blur)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.noActive, lineWidth: 1)
                )
            }
        }
        .foregroundColor(.foreground)
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        NowPlayingContent(song: song)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            onSizeChange(geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            onSizeChange(newWidth)
                        }
                }
            )
    }
}

// MARK: - Visible Now Playing Content

/// A view that displays now playing content with a fixed, animated width and transition.
struct VisibleNowPlayingContent: View {
    let song: NowPlayingSong
    let width: CGFloat

    var body: some View {
        NowPlayingContent(song: song)
            .frame(width: width, height: 38)
            .animation(.easeOut(duration: 0.08), value: song)
            .transition(.blurReplace)
    }
}

// MARK: - Album Art View

/// A view that displays the album art with a fade animation and a pause indicator if needed.
/// Supports both NSImage (from MediaRemote) and URL (from AppleScript fallback).
struct AlbumArtView: View {
    let song: NowPlayingSong

    var body: some View {
        ZStack {
            // Prefer NSImage from MediaRemote, fall back to URL
            if let image = song.albumArtImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                FadeAnimatedCachedImage(
                    url: song.albumArtURL,
                    targetSize: CGSize(width: 20, height: 20)
                )
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Song Text View

/// A view that displays the song title and artist.
struct SongTextView: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {

        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                Text(song.title)
                    .font(.system(size: 11))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(song.artist)
                    .opacity(0.8)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(song.artist + " — " + song.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // Disable animations for text changes.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

// MARK: - Preview

struct NowPlayingWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            NowPlayingWidget()
        }
        .frame(width: 500, height: 100)
    }
}
