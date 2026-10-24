import SwiftUI

public struct CardView: View {
    public let card: PhotoCard
    public let isTopCard: Bool
    public let onSwipe: (SwipeDecision) -> Void
    
    @State private var offset: CGSize = .zero
    
    private let swipeThreshold: CGFloat = 80
    private let emeraldGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    private let crimsonRed = Color(red: 0.95, green: 0.25, blue: 0.25)
    
    public init(card: PhotoCard, isTopCard: Bool, onSwipe: @escaping (SwipeDecision) -> Void) {
        self.card = card
        self.isTopCard = isTopCard
        self.onSwipe = onSwipe
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Card Deep Dark Background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(white: 0.08))
                
                // Photo Image: 100% Visible & Never Cropped
                if let image = card.image {
                    // Soft blurred ambient glow filling the card
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 28)
                        .opacity(0.35)
                    
                    // True full photo (contentMode: .fit) so nothing is ever cropped
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Chargement...")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Bottom Gradient for crisp text readability
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.1),
                        Color.black.opacity(0.85)
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // Metadata Overlay (Bottom)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if card.isScreenshot {
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
                
                // SWIPE STAMPS
                if isTopCard {
                    // KEEP Stamp (Right drag)
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("GARDER")
                    }
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(emeraldGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(emeraldGreen, lineWidth: 3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: emeraldGreen.opacity(0.6), radius: 8)
                    .rotationEffect(.degrees(-15))
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(Double(min(max(offset.width / swipeThreshold, 0), 1)))
                    
                    // DELETE Stamp (Left drag)
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("JETER")
                    }
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(crimsonRed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(crimsonRed, lineWidth: 3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: crimsonRed.opacity(0.6), radius: 8)
                    .rotationEffect(.degrees(15))
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(Double(min(max(-offset.width / swipeThreshold, 0), 1)))
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
                    .onChanged { gesture in
                        offset = gesture.translation
                    }
                    .onEnded { gesture in
                        if gesture.translation.width > swipeThreshold {
                            dismissRight(geometry: geometry)
                        } else if gesture.translation.width < -swipeThreshold {
                            dismissLeft(geometry: geometry)
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) {
                                offset = .zero
                            }
                        }
                    }
                : nil
            )
        }
    }
    
    private func dismissRight(geometry: GeometryProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            offset = CGSize(width: geometry.size.width * 1.3, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            onSwipe(.keep)
        }
    }
    
    private func dismissLeft(geometry: GeometryProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            offset = CGSize(width: -geometry.size.width * 1.3, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            onSwipe(.delete)
        }
    }
}
