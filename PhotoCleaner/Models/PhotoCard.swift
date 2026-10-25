import Foundation
import Photos
import UIKit

public struct PhotoCard: Identifiable, Equatable {
    public var id: String { asset.localIdentifier }
    public let asset: PHAsset
    public var image: UIImage?
    public var iCloudDownloadProgress: Double = 0.0

    public var creationDate: Date? {
        asset.creationDate
    }

    public var formattedDate: String {
        guard let date = asset.creationDate else { return "Date inconnue" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public var relativeDate: String {
        guard let date = asset.creationDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    public var isScreenshot: Bool {
        asset.mediaSubtypes.contains(.photoScreenshot)
    }

    public var isScreenRecording: Bool {
        if #available(iOS 15.0, *) {
            return asset.mediaSubtypes.contains(.videoScreenRecording)
        }
        return false
    }

    public var isLivePhoto: Bool {
        asset.mediaSubtypes.contains(.photoLive)
    }

    public var isFavorite: Bool {
        asset.isFavorite
    }

    public var isVideo: Bool {
        asset.mediaType == .video
    }

    public var dimensions: String {
        "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }

    public var videoDuration: String? {
        guard isVideo else { return nil }
        let totalSeconds = Int(asset.duration.rounded())
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    public var isDownloadingFromICloud: Bool {
        iCloudDownloadProgress > 0 && iCloudDownloadProgress < 1.0
    }

    public static func == (lhs: PhotoCard, rhs: PhotoCard) -> Bool {
        lhs.id == rhs.id && lhs.image == rhs.image && lhs.iCloudDownloadProgress == rhs.iCloudDownloadProgress
    }
}
