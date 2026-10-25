import SwiftUI
import AVKit

// MARK: - Gesture-Safe Native AVPlayer View
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

public struct CardView: View {
    public let card: PhotoCard
    public let isTopCard: Bool
    public let photoService: PhotoLibraryService?
    public let onSwipe: (SwipeDecision) -> Void

    @State private var offset: CGSize = .zero
    @State private var player: AVPlayer? = nil
    @State private var isMuted: Bool = true
    @State private var isVideoLoaded: Bool = false

    private let swipeThreshold: CGFloat = 80
    private let emeraldGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    private let crimsonRed = Color(red: 0.95, green: 0.25, blue: 0.25)

    public init(
        card: PhotoCard,
        isTopCard: Bool,
        photoService: PhotoLibraryService? = nil,
        onSwipe: @escaping (SwipeDecision) -> Void
    ) {
        self.card = card
        self.isTopCard = isTopCard
        self.photoService = photoService
        self.onSwipe = onSwipe
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Dark card background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(white: 0.08))

                if card.isVideo {
                    videoContent(geometry: geometry)
                } else {
                    photoContent(geometry: geometry)
                }

                // Bottom gradient for metadata contrast
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.1),
                        Color.black.opacity(0.85)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Metadata overlay
                metadataOverlay
                    .allowsHitTesting(false)

                // Audio Mute/Unmute Button for Videos
                if card.isVideo && isTopCard && player != nil {
                    VStack {
                        HStack {
                            Button {
                                isMuted.toggle()
                                player?.isMuted = isMuted
                            } label: {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.65))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            .padding(14)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // iCloud download progress indicator
                if card.isDownloadingFromICloud {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                                Text("iCloud \(Int(card.iCloudDownloadProgress * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(14)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                // Swipe stamps
                if isTopCard {
                    keepStamp
                    deleteStamp
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            .offset(x: offset.width, y: offset.height * 0.3)
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .gesture(
                isTopCard ?
                DragGesture()
                    .onChanged { gesture in offset = gesture.translation }
                    .onEnded { gesture in
                        if gesture.translation.width > swipeThreshold {
                            dismissRight(geometry: geometry)
                        } else if gesture.translation.width < -swipeThreshold {
                            dismissLeft(geometry: geometry)
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) { offset = .zero }
                        }
                    }
                : nil
            )
            .onAppear {
                if card.isVideo && isTopCard {
                    setupVideoPlayer()
                }
            }
            .onChange(of: isTopCard) { newValue in
                if newValue && card.isVideo {
                    setupVideoPlayer()
                } else {
                    stopVideoPlayer()
                }
            }
            .onDisappear {
                stopVideoPlayer()
            }
        }
    }

    // MARK: - Video Playback Setup & Loop

    private func setupVideoPlayer() {
        guard card.isVideo, player == nil else { return }

        photoService?.requestPlayerItem(for: card.asset) { item in
            guard let item = item else { return }
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = isMuted
            newPlayer.actionAtItemEnd = .none

            // Loop video continuously
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }

            self.player = newPlayer
            self.isVideoLoaded = true
            newPlayer.play()
        }
    }

    private func stopVideoPlayer() {
        player?.pause()
        player = nil
        isVideoLoaded = false
    }

    // MARK: - Photo Content

    @ViewBuilder
    private func photoContent(geometry: GeometryProxy) -> some View {
        if let image = card.image {
            // Blurred ambient glow behind
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 28)
                .opacity(0.35)

            // Full photo without any cropping
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
            loadingPlaceholder(label: "Chargement...")
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private func videoContent(geometry: GeometryProxy) -> some View {
        ZStack {
            // Blurred ambient glow from thumbnail
            if let image = card.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .blur(radius: 28)
                    .opacity(0.35)
            }

            // Active Video Playback Layer
            if let player = player, isVideoLoaded {
                PlayerLayerView(player: player)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else if let image = card.image {
                // Static thumbnail while player buffers
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else {
                loadingPlaceholder(label: "Chargement vidéo...")
            }
        }
    }

    private func loadingPlaceholder(label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Overlay

    private var metadataOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if card.isVideo {
                    HStack(spacing: 4) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(card.isScreenRecording ? "CAPTURE VIDÉO" : "VIDÉO")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(card.isScreenRecording ? Color.indigo.opacity(0.85) : Color.purple.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                } else if card.isScreenshot {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 10, weight: .bold))
                        Text("CAPTURE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                if card.isLivePhoto {
                    HStack(spacing: 4) {
                        Image(systemName: "livephoto")
                            .font(.system(size: 10, weight: .bold))
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }

                if card.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.pink)
                        .padding(5)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }

                Spacer()

                // Duration for videos
                if let duration = card.videoDuration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(duration)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                }

                Text(card.dimensions)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.formattedDate)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                if !card.relativeDate.isEmpty {
                    Text(card.relativeDate.capitalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(18)
    }

    // MARK: - Stamps

    private var keepStamp: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
            Text("GARDER")
        }
        .font(.system(size: 24, weight: .black, design: .rounded))
        .foregroundColor(emeraldGreen)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(emeraldGreen, lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: emeraldGreen.opacity(0.6), radius: 8)
        .rotationEffect(.degrees(-15))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(Double(min(max(offset.width / swipeThreshold, 0), 1)))
        .allowsHitTesting(false)
    }

    private var deleteStamp: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
            Text("JETER")
        }
        .font(.system(size: 24, weight: .black, design: .rounded))
        .foregroundColor(crimsonRed)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(crimsonRed, lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: crimsonRed.opacity(0.6), radius: 8)
        .rotationEffect(.degrees(15))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .opacity(Double(min(max(-offset.width / swipeThreshold, 0), 1)))
        .allowsHitTesting(false)
    }

    // MARK: - Dismiss

    private func dismissRight(geometry: GeometryProxy) {
        stopVideoPlayer()
        withAnimation(.easeOut(duration: 0.12)) {
            offset = CGSize(width: geometry.size.width * 1.3, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { onSwipe(.keep) }
    }

    private func dismissLeft(geometry: GeometryProxy) {
        stopVideoPlayer()
        withAnimation(.easeOut(duration: 0.12)) {
            offset = CGSize(width: -geometry.size.width * 1.3, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { onSwipe(.delete) }
    }
}
