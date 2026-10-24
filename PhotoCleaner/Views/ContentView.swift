import SwiftUI
import Photos

public struct ContentView: View {
    @StateObject private var photoService = PhotoLibraryService()
    @State private var showTrashSheet: Bool = false
    @State private var showStatsSheet: Bool = false
    
    private let emeraldGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    private let crimsonRed = Color(red: 0.95, green: 0.25, blue: 0.25)
    private let ambientGlow = Color(red: 0.2, green: 0.3, blue: 0.85)
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Fond sombre OLED avec lueur d'ambiance subtile
                Color.black.ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [ambientGlow.opacity(0.16), Color.black]),
                    center: .top,
                    startRadius: 20,
                    endRadius: 460
                )
                .ignoresSafeArea()
                
                switch photoService.authorizationStatus {
                case .authorized, .limited:
                    mainDeckView
                case .notDetermined:
                    permissionPromptView
                case .denied, .restricted:
                    permissionDeniedView
                @unknown default:
                    permissionPromptView
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTrashSheet) {
            TrashReviewSheet(photoService: photoService)
        }
        .sheet(isPresented: $showStatsSheet) {
            StatsView(photoService: photoService)
        }
    }
    
    // MARK: - Main Deck View
    
    private var mainDeckView: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(alignment: .center) {
                // Bouton Statistiques / Progression
                Button {
                    photoService.triggerHapticFeedback(.light)
                    showStatsSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(emeraldGreen)
                            .frame(width: 7, height: 7)
                            .shadow(color: emeraldGreen, radius: 4)
                        
                        Text("\(photoService.remainingUnreviewedCount)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Text("RESTANTES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                
                Spacer()
                
                Text("PhotoCleaner")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Spacer()
                
                // Bouton Corbeille
                Button {
                    photoService.triggerHapticFeedback(.light)
                    showTrashSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(photoService.pendingDeleteCount > 0 ? crimsonRed : .white.opacity(0.6))
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        
                        if photoService.pendingDeleteCount > 0 {
                            Text("\(photoService.pendingDeleteCount)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(crimsonRed)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -4)
                                .shadow(color: crimsonRed.opacity(0.5), radius: 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            // Zone des Cartes
            if photoService.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text("Mélange aléatoire des photos...")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if photoService.activeCards.isEmpty {
                allDoneView
            } else {
                ZStack {
                    ForEach(Array(photoService.activeCards.prefix(2).enumerated().reversed()), id: \.element.id) { index, card in
                        let isTop = (index == 0)
                        CardView(
                            card: card,
                            isTopCard: isTop,
                            onSwipe: { decision in
                                photoService.swipeCurrentCard(decision: decision)
                            }
                        )
                        .zIndex(Double(photoService.activeCards.count - index))
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Barre de boutons d'action inférieure
            HStack(spacing: 24) {
                // Bouton Undo (Annuler le dernier swipe)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        photoService.undoLastSwipe()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: Color.orange.opacity(0.2), radius: 8)
                }
                .disabled(!StorageService.shared.canUndo())
                .opacity(StorageService.shared.canUndo() ? 1.0 : 0.3)
                
                // Bouton Jeter / Poubelle (Gauche)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        photoService.swipeCurrentCard(decision: .delete)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.95, green: 0.25, blue: 0.25), Color(red: 0.75, green: 0.15, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: crimsonRed.opacity(0.45), radius: 12, y: 4)
                }
                .disabled(photoService.activeCards.isEmpty)
                
                // Bouton Garder (Droite)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        photoService.swipeCurrentCard(decision: .keep)
                    }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 68, height: 68)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 0.09, green: 0.61, blue: 0.29)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: emeraldGreen.opacity(0.45), radius: 12, y: 4)
                }
                .disabled(photoService.activeCards.isEmpty)
            }
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Écran de fin (Toutes les photos triées)
    
    private var allDoneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.5), radius: 12)
            
            Text("Galerie entièrement triée !")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text("Vous avez classé toutes les photos existantes. Les nouveaux clichés pris avec votre appareil apparaîtront automatiquement ici.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            
            if photoService.pendingDeleteCount > 0 {
                Button {
                    photoService.triggerHapticFeedback(.medium)
                    showTrashSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("Vider la corbeille (\(photoService.pendingDeleteCount))")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(crimsonRed)
                    .clipShape(Capsule())
                    .shadow(color: crimsonRed.opacity(0.4), radius: 10, y: 4)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Permissions
    
    private var permissionPromptView: some View {
        VStack(spacing: 22) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72))
                .foregroundColor(ambientGlow)
                .shadow(color: ambientGlow.opacity(0.6), radius: 16)
            
            Text("Bienvenue sur PhotoCleaner")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.white)
            
            Text("Nettoyez votre pellicule rapidement façon Tinder. Swipez à droite pour garder, à gauche pour supprimer. Tout est mémorisé.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            
            Button {
                photoService.triggerHapticFeedback(.medium)
                photoService.requestPermission()
            } label: {
                Text("Autoriser l'accès aux photos")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ambientGlow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: ambientGlow.opacity(0.4), radius: 12, y: 4)
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            
            Text("Accès aux photos requis")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("PhotoSwipe a besoin de l'accès à vos photos pour fonctionner. Activez l'accès dans les Réglages de votre iPhone.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
