import Foundation

public enum SwipeDecision: String, Codable {
    case keep
    case delete
}

public struct SwipeRecord: Codable, Identifiable {
    public var id: String { assetId }
    public let assetId: String
    public let decision: SwipeDecision
    public let timestamp: Date
}

public struct StorageData: Codable {
    public var reviewedIDs: Set<String>
    public var pendingDeleteIDs: Set<String>
    public var history: [SwipeRecord]
    
    public init(reviewedIDs: Set<String> = [], pendingDeleteIDs: Set<String> = [], history: [SwipeRecord] = []) {
        self.reviewedIDs = reviewedIDs
        self.pendingDeleteIDs = pendingDeleteIDs
        self.history = history
    }
}

public final class StorageService {
    public static let shared = StorageService()
    
    private let fileName = "photoswipe_data.json"
    private var data: StorageData
    private let queue = DispatchQueue(label: "com.photoswipe.storageservice", qos: .utility)
    
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(fileName)
    }
    
    private init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photoswipe_data.json")
        if let loaded = Self.loadFromDisk(url: url) {
            self.data = loaded
        } else {
            self.data = StorageData()
        }
    }
    
    private static func loadFromDisk(url: URL) -> StorageData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let fileData = try Data(contentsOf: url)
            return try JSONDecoder().decode(StorageData.self, from: fileData)
        } catch {
            print("Failed to load storage data: \(error)")
            return nil
        }
    }
    
    private func saveToDisk() {
        let currentData = self.data
        let url = self.fileURL
        queue.async {
            do {
                let encoded = try JSONEncoder().encode(currentData)
                try encoded.write(to: url, options: [.atomicWrite])
            } catch {
                print("Failed to save storage data: \(error)")
            }
        }
    }
    
    // MARK: - Queries
    
    public func isReviewed(assetId: String) -> Bool {
        data.reviewedIDs.contains(assetId)
    }
    
    public func getReviewedCount() -> Int {
        data.reviewedIDs.count
    }
    
    public func getPendingDeleteIDs() -> Set<String> {
        data.pendingDeleteIDs
    }
    
    public func canUndo() -> Bool {
        !data.history.isEmpty
    }
    
    // MARK: - Mutations
    
    public func recordSwipe(assetId: String, decision: SwipeDecision) {
        data.reviewedIDs.insert(assetId)
        if decision == .delete {
            data.pendingDeleteIDs.insert(assetId)
        }
        data.history.append(SwipeRecord(assetId: assetId, decision: decision, timestamp: Date()))
        saveToDisk()
    }
    
    public func undoLastSwipe() -> SwipeRecord? {
        guard let last = data.history.popLast() else { return nil }
        
        data.reviewedIDs.remove(last.assetId)
        if last.decision == .delete {
            data.pendingDeleteIDs.remove(last.assetId)
        }
        saveToDisk()
        return last
    }
    
    public func removeFromPendingDelete(assetId: String) {
        data.pendingDeleteIDs.remove(assetId)
        saveToDisk()
    }
    
    public func markDeletionsCompleted(assetIds: Set<String>) {
        data.pendingDeleteIDs.subtract(assetIds)
        saveToDisk()
    }
    
    public func resetAll() {
        data = StorageData()
        saveToDisk()
    }
}
