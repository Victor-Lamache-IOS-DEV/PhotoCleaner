import Foundation
import Photos
import UIKit
import SwiftUI

@MainActor
public final class PhotoLibraryService: ObservableObject {
    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public var activeCards: [PhotoCard] = []
    @Published public var totalGalleryPhotos: Int = 0
    @Published public var remainingUnreviewedCount: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDeleteCount: Int = 0
    
    private let imageManager = PHCachingImageManager()
    private var allUnreviewedAssetIDs: [String] = []
    private var allAssetsDict: [String: PHAsset] = [:]
    
    // High-resolution size for smooth display
    private let targetImageSize = CGSize(width: 1170, height: 1600)
    
    public init() {
        checkAuthorization()
    }
    
    public func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public func triggerNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    
    public func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        self.pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
        
        if status == .authorized || status == .limited {
            loadLibrary()
        }
    }
    
    public func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self?.loadLibrary()
                }
            }
        }
    }
    
    // MARK: - Library Loading & Randomization
    
    public func loadLibrary() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            
            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            let totalCount = allAssets.count
            
            var unreviewed: [String] = []
            var assetMap: [String: PHAsset] = [:]
            
            allAssets.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                assetMap[id] = asset
                if !StorageService.shared.isReviewed(assetId: id) {
                    unreviewed.append(id)
                }
            }
            
            // Randomize order of unreviewed photos
            unreviewed.shuffle()
            
            DispatchQueue.main.async {
                self.allAssetsDict = assetMap
                self.allUnreviewedAssetIDs = unreviewed
                self.totalGalleryPhotos = totalCount
                self.remainingUnreviewedCount = unreviewed.count
                self.pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
                self.isLoading = false
                
                self.replenishActiveCards()
            }
        }
    }
    
    // MARK: - Card Buffer Management
    
    private func replenishActiveCards() {
        while activeCards.count < 5 && !allUnreviewedAssetIDs.isEmpty {
            let nextId = allUnreviewedAssetIDs.removeFirst()
            if let asset = allAssetsDict[nextId] {
                let card = PhotoCard(asset: asset)
                activeCards.append(card)
                loadImageForCard(assetId: nextId)
            }
        }
        remainingUnreviewedCount = allUnreviewedAssetIDs.count + activeCards.count
    }
    
    private func loadImageForCard(assetId: String) {
        guard let asset = allAssetsDict[assetId] else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetImageSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            
            DispatchQueue.main.async {
                if let index = self.activeCards.firstIndex(where: { $0.id == assetId }) {
                    self.activeCards[index].image = image
                }
            }
        }
    }
    
    // MARK: - Swipe Actions
    
    public func swipeCurrentCard(decision: SwipeDecision) {
        guard !activeCards.isEmpty else { return }
        
        let swipedCard = activeCards.removeFirst()
        StorageService.shared.recordSwipe(assetId: swipedCard.id, decision: decision)
        
        if decision == .keep {
            triggerHapticFeedback(.light)
        } else {
            triggerHapticFeedback(.medium)
        }
        
        pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
        replenishActiveCards()
    }
    
    public func undoLastSwipe() {
        guard let record = StorageService.shared.undoLastSwipe() else { return }
        guard let asset = allAssetsDict[record.assetId] else { return }
        
        triggerHapticFeedback(.medium)
        let card = PhotoCard(asset: asset)
        activeCards.insert(card, at: 0)
        loadImageForCard(assetId: record.assetId)
        
        pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
        remainingUnreviewedCount = allUnreviewedAssetIDs.count + activeCards.count
    }
    
    // MARK: - Safe Batch Deletion (Apple Native Sheet)
    
    public func deletePendingPhotos(completion: @escaping (Bool) -> Void) {
        let pendingIDs = Array(StorageService.shared.getPendingDeleteIDs())
        guard !pendingIDs.isEmpty else {
            completion(true)
            return
        }
        
        let assetsToDelete = PHAsset.fetchAssets(withLocalIdentifiers: pendingIDs, options: nil)
        guard assetsToDelete.count > 0 else {
            StorageService.shared.markDeletionsCompleted(assetIds: Set(pendingIDs))
            self.pendingDeleteCount = 0
            completion(true)
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.triggerNotificationFeedback(.success)
                    StorageService.shared.markDeletionsCompleted(assetIds: Set(pendingIDs))
                    self?.pendingDeleteCount = 0
                    for id in pendingIDs {
                        self?.allAssetsDict.removeValue(forKey: id)
                    }
                    completion(true)
                } else {
                    self?.triggerNotificationFeedback(.error)
                    if let error = error {
                        print("Failed to delete assets: \(error)")
                    }
                    completion(false)
                }
            }
        }
    }
    
    public func getPendingDeleteAssets() -> [PHAsset] {
        let ids = Array(StorageService.shared.getPendingDeleteIDs())
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var result: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            result.append(asset)
        }
        return result
    }
    
    public func resetReviewedHistory() {
        triggerNotificationFeedback(.warning)
        StorageService.shared.resetAll()
        loadLibrary()
    }
}
