import SwiftUI
import Photos

public struct TrashReviewSheet: View {
    @ObservedObject public var photoService: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    
    @State private var pendingAssets: [PHAsset] = []
    @State private var isDeleting: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 6)
    ]
    
    public init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if pendingAssets.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "trash.slash.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text("Corbeille vide")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Les photos que vous glissez vers la gauche apparaîtront ici pour confirmation avant suppression.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Notice de sécurité Apple
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sécurité Apple 30 jours")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Les photos supprimées vont dans l'album « Supprimés récemment » de votre iPhone.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        
                        // Grille des photos
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(pendingAssets, id: \.localIdentifier) { asset in
                                    TrashThumbnailItem(asset: asset) {
                                        photoService.triggerHapticFeedback(.light)
                                        StorageService.shared.removeFromPendingDelete(assetId: asset.localIdentifier)
                                        pendingAssets.removeAll(where: { $0.localIdentifier == asset.localIdentifier })
                                        photoService.pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                        }
                        
                        // Bouton d'action fixe en bas
                        VStack(spacing: 8) {
                            Button {
                                confirmEmptyTrash()
                            } label: {
                                HStack(spacing: 8) {
                                    if isDeleting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        Text("Supprimer définitivement (\(pendingAssets.count))")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.95, green: 0.25, blue: 0.25), Color(red: 0.75, green: 0.15, blue: 0.15)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.red.opacity(0.4), radius: 10, y: 4)
                            }
                            .disabled(isDeleting)
                        }
                        .padding(16)
                        .background(
                            Color.black
                                .opacity(0.9)
                                .shadow(color: Color.black, radius: 12, y: -4)
                        )
                    }
                }
            }
            .navigationTitle("Corbeille (\(pendingAssets.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                loadPending()
            }
            .alert("Suppression", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadPending() {
        pendingAssets = photoService.getPendingDeleteAssets()
    }
    
    private func confirmEmptyTrash() {
        isDeleting = true
        photoService.deletePendingPhotos { success in
            isDeleting = false
            if success {
                loadPending()
                if pendingAssets.isEmpty {
                    dismiss()
                }
            } else {
                alertMessage = "La suppression a été annulée ou refusée par le système."
                showAlert = true
            }
        }
    }
}

private struct TrashThumbnailItem: View {
    let asset: PHAsset
    let onRestore: () -> Void
    
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(white: 0.15))
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Bouton restaurer (remettre dans la galerie)
            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .padding(5)
            }
        }
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 220, height: 220),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                self.thumbnail = image
            }
        }
    }
}
