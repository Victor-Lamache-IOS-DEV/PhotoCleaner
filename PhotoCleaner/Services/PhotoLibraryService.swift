import Foundation
import Photos
import UIKit
import SwiftUI
import AVKit

// MARK: - Media Category
public enum MediaKind: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Vidéos"
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .photos: return "photo.stack"
        case .videos: return "play.rectangle.fill"
        }
    }
}

// MARK: - Browse Mode
public enum BrowseMode: String, CaseIterable, Identifiable {
    // Photos
    case photoRandom           = "Aléatoire"
    case photoLastWeek         = "Cette semaine"
    case photoLastMonth        = "Ce mois"
    case photoScreenshots      = "Captures d'écran"
    case photoWebSaved         = "Enregistrées du web"
    case photoHeaviest         = "Plus gourmandes"
    
    // Videos
    case videoRandom           = "Aléatoire (Vidéos)"
    case videoLastWeek         = "Cette semaine (Vidéos)"
    case videoLastMonth        = "Ce mois (Vidéos)"
    case videoScreenRecordings = "Enregistrements d'écran"
    case videoHeaviest         = "Plus gourmandes (Vidéos)"

    public var id: String { rawValue }

    public var isVideo: Bool {
        switch self {
        case .videoRandom, .videoLastWeek, .videoLastMonth, .videoScreenRecordings, .videoHeaviest:
            return true
        default:
            return false
        }
    }

    public var icon: String {
        switch self {
        case .photoRandom:           return "shuffle"
        case .photoLastWeek:         return "calendar.badge.clock"
        case .photoLastMonth:        return "calendar"
        case .photoScreenshots:      return "camera.viewfinder"
        case .photoWebSaved:         return "arrow.down.circle"
        case .photoHeaviest:         return "scalemass.fill"
        case .videoRandom:           return "shuffle"
        case .videoLastWeek:         return "calendar.badge.clock"
        case .videoLastMonth:        return "calendar"
        case .videoScreenRecordings: return "record.circle"
        case .videoHeaviest:         return "scalemass.fill"
        }
    }

    public var shortLabel: String {
        switch self {
        case .photoRandom:           return "Aléatoire"
        case .photoLastWeek:         return "Semaine"
        case .photoLastMonth:        return "Ce mois"
        case .photoScreenshots:      return "Captures"
        case .photoWebSaved:         return "Web"
        case .photoHeaviest:         return "Lourdes"
        case .videoRandom:           return "Vidéos · Aléatoire"
        case .videoLastWeek:         return "Vidéos · Semaine"
        case .videoLastMonth:        return "Vidéos · Mois"
        case .videoScreenRecordings: return "Recs Écran"
        case .videoHeaviest:         return "Vidéos · Lourdes"
        }
    }

    public var cleanTitle: String {
        switch self {
        case .photoRandom:           return "Aléatoire"
        case .photoLastWeek:         return "Cette semaine"
        case .photoLastMonth:        return "Ce mois"
        case .photoScreenshots:      return "Captures d'écran"
        case .photoWebSaved:         return "Enregistrées du web"
        case .photoHeaviest:         return "Plus gourmandes"
        case .videoRandom:           return "Aléatoire"
        case .videoLastWeek:         return "Cette semaine"
        case .videoLastMonth:        return "Ce mois"
        case .videoScreenRecordings: return "Enregistrements d'écran"
        case .videoHeaviest:         return "Plus gourmandes"
        }
    }
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
    @Published public var browseMode: BrowseMode = .photoRandom {
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

        let currentMode = self.browseMode
        let isVideo = currentMode.isVideo
        let mediaType: PHAssetMediaType = isVideo ? .video : .image

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = Self.buildPredicate(for: currentMode)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let allAssets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)
            let totalCount = allAssets.count

            var unreviewed: [String] = []
            var assetMap: [String: PHAsset] = [:]

            allAssets.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                assetMap[id] = asset
                if !StorageService.shared.isReviewed(assetId: id) && !unreviewed.contains(id) {
                    unreviewed.append(id)
                }
            }

            // Ordering based on mode
            switch currentMode {
            case .photoRandom, .videoRandom:
                unreviewed.shuffle()
            case .photoHeaviest:
                unreviewed.sort {
                    guard let a1 = assetMap[$0], let a2 = assetMap[$1] else { return false }
                    return (a1.pixelWidth * a1.pixelHeight) > (a2.pixelWidth * a2.pixelHeight)
                }
            case .videoHeaviest:
                // Weight videos by duration * resolution
                unreviewed.sort {
                    guard let a1 = assetMap[$0], let a2 = assetMap[$1] else { return false }
                    let weight1 = a1.duration * Double(a1.pixelWidth * a1.pixelHeight)
                    let weight2 = a2.duration * Double(a2.pixelWidth * a2.pixelHeight)
                    return weight1 > weight2
                }
            case .photoLastWeek, .photoLastMonth, .photoScreenshots, .photoWebSaved,
                 .videoLastWeek, .videoLastMonth, .videoScreenRecordings:
                // Already sorted chronologically descending by fetchOptions
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

    // MARK: - Predicates

    private static func buildPredicate(for mode: BrowseMode) -> NSPredicate {
        let now = Date()
        let calendar = Calendar.current

        switch mode {
        case .photoRandom, .photoHeaviest, .videoRandom, .videoHeaviest:
            return NSPredicate(value: true)

        case .photoLastWeek, .videoLastWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return NSPredicate(format: "creationDate >= %@", weekAgo as NSDate)

        case .photoLastMonth, .videoLastMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return NSPredicate(format: "creationDate >= %@", monthAgo as NSDate)

        case .photoScreenshots:
            return NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)

        case .videoScreenRecordings:
            if #available(iOS 15.0, *) {
                return NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.videoScreenRecording.rawValue)
            } else {
                return NSPredicate(value: true)
            }

        case .photoWebSaved:
            return NSPredicate(format: "((mediaSubtype & %d) == 0)", PHAssetMediaSubtype.photoScreenshot.rawValue)
        }
    }

    // MARK: - Card Buffer Management

    private func replenishActiveCards() {
        let bufferSize = 3
        while activeCards.count < bufferSize && !allUnreviewedAssetIDs.isEmpty {
            let nextId = allUnreviewedAssetIDs.removeFirst()
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

        if let oldRequestID = activeImageRequestIDs[assetId] {
            imageManager.cancelImageRequest(oldRequestID)
        }

        // Fast thumbnail pass
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

        // Full HD quality pass (downloads from iCloud if needed)
        let hdOptions = PHImageRequestOptions()
        hdOptions.deliveryMode = .highQualityFormat
        hdOptions.isNetworkAccessAllowed = true
        hdOptions.isSynchronous = false
        hdOptions.resizeMode = .exact
        hdOptions.progressHandler = { progress, _, _, _ in
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

    // MARK: - Video Playback Provider

    public func requestPlayerItem(for asset: PHAsset, completion: @escaping (AVPlayerItem?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        imageManager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async {
                completion(item)
            }
        }
    }

    // MARK: - Swipe Actions

    public func swipeCurrentCard(decision: SwipeDecision) {
        guard !activeCards.isEmpty else { return }

        let swipedCard = activeCards.removeFirst()

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

        guard !activeCards.contains(where: { $0.id == record.assetId }) else { return }

        let card = PhotoCard(asset: asset)
        activeCards.insert(card, at: 0)
        loadImageForCard(assetId: record.assetId)

        pendingDeleteCount = StorageService.shared.getPendingDeleteIDs().count
        remainingUnreviewedCount = allUnreviewedAssetIDs.count + activeCards.count
    }

    // MARK: - Safe Batch Deletion

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
