import SwiftUI

public struct StatsView: View {
    @ObservedObject public var photoService: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirmation: Bool = false
    
    public init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    Section {
                        HStack {
                            Text("Total photos détectées")
                            Spacer()
                            Text("\(photoService.totalGalleryPhotos)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        HStack {
                            Text("Photos classées")
                            Spacer()
                            let reviewed = StorageService.shared.getReviewedCount()
                            Text("\(reviewed)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("Restantes à trier")
                            Spacer()
                            Text("\(photoService.remainingUnreviewedCount)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        
                        HStack {
                            Text("En attente de suppression")
                            Spacer()
                            Text("\(photoService.pendingDeleteCount)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    } header: {
                        Text("Vue d'ensemble")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    
                    Section {
                        let total = max(photoService.totalGalleryPhotos, 1)
                        let reviewed = StorageService.shared.getReviewedCount()
                        let progress = Double(reviewed) / Double(total)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Progression du tri")
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            ProgressView(value: progress)
                                .tint(.green)
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            
                            Text("\(reviewed) sur \(total) photos triées")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Avancement")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    
                    Section {
                        Text("L'ordre d'affichage est aléatoire. Toutes vos décisions (Garder ou Jeter) sont conservées en local. Vous ne reverrez jamais une photo déjà classée lors de vos prochaines sessions.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    } header: {
                        Text("Mémoire & Aléatoire")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    
                    Section {
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Réinitialiser l'historique de tri")
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("Zone de réinitialisation")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Statistiques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                }
            }
            .confirmationDialog(
                "Réinitialiser l'historique ?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Tout réinitialiser", role: .destructive) {
                    photoService.resetReviewedHistory()
                    dismiss()
                }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Vos photos ne seront PAS supprimées. Cela permettra simplement de toutes les re-swiper depuis le début.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
