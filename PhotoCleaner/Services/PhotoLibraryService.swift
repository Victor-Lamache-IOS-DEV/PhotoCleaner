import Foundation
import Photos
import UIKit
import SwiftUI

// MARK: - Browse Mode
public enum BrowseMode: String, CaseIterable, Identifiable {
    case random        = "Aléatoire"
    case lastMonth     = "Ce mois"
    case lastWeek      = "Cette semaine"
    case screenshots   = "Captures d'écran"
    case webSaved      = "Enregistrées du web"
    case heaviest      = "Plus gourmandes"
    case videos        = "Vidéos"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .random:      return "shuffle"
        case .lastMonth:   return "calendar"
        case .lastWeek:    return "calendar.badge.clock"
        case .screenshots: return "camera.viewfinder"
        case .webSaved:    return "arrow.down.circle"
        case .heaviest:    return "scalemass.fill"
        case .videos:      return "play.rectangle.fill"
        }
    }

    public var isVideo: Bool { self == .videos }
}

@MainActor
public final class PhotoLibraryService: ObservableObject {
    @Published public var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public var activeCards: [PhotoCard] = []
    @Published public var totalGalleryPhotos: Int = 0
    @Published public var remainingUnreviewedCount: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDeleteCount: Int = 0
    @Published public var browseMode: BrowseMode = .random {
        didSet {
            if oldValue != browseMode {
                reloadForCurrentMode()
            }
        }
    }

    private let imageManager = PHCachingImageManager()
    private var allUnreviewedAssetIDs: [String] = []
    private var allAssetsDict: [String: PHAsset] = [:]
    private var activeImageRequestIDs: [String: PHImageRequestID] = [:]

    // High-resolution size for smooth display
    private let targetImageSize = CGSize(width: 1170, height: 1600)

    public init() {
        imageManager.allowsCachingHighQualityImages = true
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

    // MARK: - Library Loading

    public func loadLibrary() {
        isLoading = true
        errorMessage = nil
        activeCards = []
        allUnreviewedAssetIDs = []
        allAssetsDict = [:]
        cancelAllImageRequests()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let isVideo = self.browseMode.isVideo
            let mediaType: PHAssetMediaType = isVideo ? .video : .image

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = Self.buildPredicate(for: self.browseMode)
            fetchOptions.sortDescriptors = Self.buildSortDescriptors(for: self.browseMode)

            let allAssets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)
            let totalCount = allAssets.count

            var unreviewed: [String] = []
            var assetMap: [String: PHAsset] = [:]

            allAssets.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                assetMap[id] = asset
                // Guard against duplicate IDs
                if !StorageService.shared.isReviewed(assetId: id) && assetMap[id] != nil && !unreviewed.contains(id) {
                    unreviewed.append(id)
                }
            }

            // Sort or shuffle based on mode
            switch self.browseMode {
            case .random:
                unreviewed.shuffle()
            case .heaviest:
                // Already sorted by resource size via sort descriptor on asset (largest first)
                // PHAsset doesn't expose byte size in predicate, we sort by pixel area as proxy
                unreviewed.sort {
                    guard let a1 = assetMap[$0], let a2 = assetMap[$1] else { return false }
                    return (a1.pixelWidth * a1.pixelHeight) > (a2.pixelWidth * a2.pixelHeight)
                }
            case .lastWeek, .lastMonth, .screenshots, .webSaved, .videos:
                // Sorted by date descending already via sort descriptor
                break
            }

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

    private func reloadForCurrentMode() {
        loadLibrary()
    }

    // MARK: - Predicates & Sort Descriptors

    private static func buildPredicate(for mode: BrowseMode) -> NSPredicate {
        let now = Date()
        let calendar = Calendar.current

        switch mode {
        case .random, .heaviest, .videos:
            return NSPredicate(value: true)

        case .lastWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return NSPredicate(format: "creationDate >= %@", weekAgo as NSDate)

        case .lastMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return NSPredicate(format: "creationDate >= %@", monthAgo as NSDate)

        case .screenshots:
            // mediaSubtype bitmask for screenshots = 8
            return NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)

        case .webSaved:
            // User library photos that were not taken with camera (no GPS typically)
            // Use albumType filtering or detect via source: PHAssetSourceType.typeUserLibrary excludes camera roll
            // We filter for images that are NOT screenshots and have no camera subtype
            let cameraSubtype = PHAssetMediaSubtype.photoHDR.rawValue |
                                PHAssetMediaSubtype.photoLive.rawValue |
                                PHAssetMediaSubtype.photoPanorama.rawValue
            return NSPredicate(format: "((mediaSubtype & %d) == 0)", PHAssetMediaSubtype.photoScreenshot.rawValue)
        }
    }

    private static func buildSortDescriptors(for mode: BrowseMode) -> [NSSortDescriptor] {
        return [NSSortDescriptor(key: "creationDate", ascending: false)]
    }

    // MARK: - Card Buffer Management

    private func replenishActiveCards() {
        let bufferSize = 3
        while activeCards.count < bufferSize && !allUnreviewedAssetIDs.isEmpty {
            let nextId = allUnreviewedAssetIDs.removeFirst()
            // Double-check we don't already have this card active (safety guard)
            guard !activeCards.contains(where: { $0.id == nextId }) else { continue }
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

        // Cancel any previous request for this card
        if let oldRequestID = activeImageRequestIDs[assetId] {
            imageManager.cancelImageRequest(oldRequestID)
        }

        // Step 1: Request low-quality thumbnail immediately for instant display
        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .fastFormat
        thumbOptions.isNetworkAccessAllowed = false
        thumbOptions.isSynchronous = false
        thumbOptions.resizeMode = .fast

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 600),
            contentMode: .aspectFit,
            options: thumbOptions
        ) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            DispatchQueue.main.async {
                if let index = self.activeCards.firstIndex(where: { $0.id == assetId }),
                   self.activeCards[index].image == nil {
                    self.activeCards[index].image = image
                }
            }
        }

        // Step 2: Request full quality (downloads from iCloud if needed)
        let hdOptions = PHImageRequestOptions()
        hdOptions.deliveryMode = .highQualityFormat
        hdOptions.isNetworkAccessAllowed = true   // ← Key: fetch from iCloud
        hdOptions.isSynchronous = false
        hdOptions.resizeMode = .exact
        hdOptions.progressHandler = { progress, _, _, _ in
            // iCloud download progress (could show in UI later)
            DispatchQueue.main.async {
                if let index = self.activeCards.firstIndex(where: { $0.id == assetId }) {
                    self.activeCards[index].iCloudDownloadProgress = progress
                }
            }
        }

        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetImageSize,
            contentMode: .aspectFit,
            options: hdOptions
        ) { [weak self] image, info in
            guard let self = self, let image = image else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                DispatchQueue.main.async {
                    if let index = self.activeCards.firstIndex(where: { $0.id == assetId }) {
                        self.activeCards[index].image = image
                        self.activeCards[index].iCloudDownloadProgress = 1.0
                    }
                    self.activeImageRequestIDs.removeValue(forKey: assetId)
                }
            }
        }

        activeImageRequestIDs[assetId] = requestID
    }

    private func cancelAllImageRequests() {
        for (_, requestID) in activeImageRequestIDs {
            imageManager.cancelImageRequest(requestID)
        }
        activeImageRequestIDs.removeAll()
    }

    // MARK: - Video Thumbnail

    public func loadVideoThumbnail(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 1200),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - Swipe Actions

    public func swipeCurrentCard(decision: SwipeDecision) {
        guard !activeCards.isEmpty else { return }

        let swipedCard = activeCards.removeFirst()

        // Cancel its image request (no longer needed)
        if let requestID = activeImageRequestIDs[swipedCard.id] {
            imageManager.cancelImageRequest(requestID)
            activeImageRequestIDs.removeValue(forKey: swipedCard.id)
        }

        StorageService.shared.recordSwipe(assetId: swipedCard.id, decision: decision)
        pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
        replenishActiveCards()
    }

    public func undoLastSwipe() {
        guard let record = StorageService.shared.undoLastSwipe() else { return }
        guard let asset = allAssetsDict[record.assetId] else { return }

        // Guard: don't add if already in active cards
        guard !activeCards.contains(where: { $0.id == record.assetId }) else { return }

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
                    if let error = error { print("Failed to delete assets: \(error)") }
                    completion(false)
                }
            }
        }
    }

    public func getPendingDeleteAssets() -> [PHAsset] {
        let ids = Array(StorageService.shared.getPendingDeleteIDs())
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var result: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in result.append(asset) }
        return result
    }

    public func resetReviewedHistory() {
        triggerNotificationFeedback(.warning)
        StorageService.shared.resetAll()
        loadLibrary()
    }
}
