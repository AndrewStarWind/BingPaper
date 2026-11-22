import Foundation

public struct WallpaperStore: Sendable {
    public let baseDirectory: URL
    public let wallpapersDirectory: URL
    public let backupsDirectory: URL
    public let historyFileURL: URL

    public init(baseDirectory: URL? = nil) {
        let resolvedBase: URL
        if let baseDirectory {
            resolvedBase = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            resolvedBase = appSupport.appendingPathComponent("BingPaper", isDirectory: true)
        }
        self.baseDirectory = resolvedBase
        self.wallpapersDirectory = resolvedBase.appendingPathComponent("Wallpapers", isDirectory: true)
        self.backupsDirectory = resolvedBase.appendingPathComponent("Backups", isDirectory: true)
        self.historyFileURL = resolvedBase.appendingPathComponent("history.json", isDirectory: false)
    }

    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: wallpapersDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    /// Returns the local destination URL for a given Bing image metadata, market, and quality.
    public func fileURL(for metadata: BingImageMetadata, market: String, preferUHD: Bool) -> URL {
        wallpapersDirectory.appendingPathComponent(metadata.localFilename(market: market, preferUHD: preferUHD))
    }

    /// Checks if the image is already downloaded and non-empty on disk.
    public func existingFileURL(for metadata: BingImageMetadata, market: String, preferUHD: Bool) -> URL? {
        let candidate = fileURL(for: metadata, market: market, preferUHD: preferUHD)
        guard FileManager.default.fileExists(atPath: candidate.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 1024 else {
            return nil
        }
        return candidate
    }

    /// Atomically saves image bytes to disk and records/updates history.
    @discardableResult
    public func saveImage(
        _ data: Data,
        metadata: BingImageMetadata,
        market: String,
        preferUHD: Bool,
        appliedAt: Date? = nil
    ) throws -> WallpaperHistoryEntry {
        try ensureDirectoriesExist()
        let destination = fileURL(for: metadata, market: market, preferUHD: preferUHD)
        try data.write(to: destination, options: .atomic)

        var history = loadHistory()
        let entry = WallpaperHistoryEntry(
            metadata: metadata,
            market: market,
            localPath: destination.path,
            downloadedAt: Date(),
            lastAppliedAt: appliedAt
        )
        history.removeAll { $0.id == entry.id || $0.localPath == entry.localPath }
        history.insert(entry, at: 0)
        try saveHistory(history)
        return entry
    }

    public func markApplied(entryID: String, at date: Date = Date()) throws {
        var history = loadHistory()
        if let idx = history.firstIndex(where: { $0.id == entryID }) {
            history[idx].lastAppliedAt = date
            try saveHistory(history)
        }
    }

    public func loadHistory() -> [WallpaperHistoryEntry] {
        guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([WallpaperHistoryEntry].self, from: data) else {
            return []
        }
        return entries.filter { FileManager.default.fileExists(atPath: $0.localPath) }
    }

    public func saveHistory(_ entries: [WallpaperHistoryEntry]) throws {
        try ensureDirectoriesExist()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: historyFileURL, options: .atomic)
    }

    /// Removes cached wallpapers older than `retentionDays`, never deleting `protectedPath`.
    @discardableResult
    public func pruneOldWallpapers(retentionDays: Int, keeping protectedPath: String?, now: Date = Date()) throws -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: wallpapersDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removedCount = 0
        var removedPaths = Set<String>()
        let normalizedProtected = protectedPath.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }

        for file in files {
            let normalizedFile = file.resolvingSymlinksInPath().standardizedFileURL.path
            if let normalizedProtected, normalizedFile == normalizedProtected {
                continue
            }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let fileDate = values?.contentModificationDate ?? values?.creationDate ?? now
            if fileDate < cutoff {
                do {
                    try fm.removeItem(at: file)
                    removedCount += 1
                    removedPaths.insert(normalizedFile)
                } catch {
                    BingPaperLog.store.warning("Failed to prune old wallpaper \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        if !removedPaths.isEmpty {
            let remaining = loadHistory().filter { entry in
                let normalizedEntry = URL(fileURLWithPath: entry.localPath).resolvingSymlinksInPath().standardizedFileURL.path
                return !removedPaths.contains(normalizedEntry)
            }
            try? saveHistory(remaining)
        }
        return removedCount
    }

    /// Deletes all cached wallpapers except the currently active one.
    @discardableResult
    public func clearCache(keeping protectedPath: String?) throws -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: wallpapersDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        let normalizedProtected = protectedPath.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        var removed = 0
        for file in files {
            let normalizedFile = file.resolvingSymlinksInPath().standardizedFileURL.path
            if normalizedFile == normalizedProtected { continue }
            try? fm.removeItem(at: file)
            removed += 1
        }
        let remaining = loadHistory().filter { entry in
            let normalizedEntry = URL(fileURLWithPath: entry.localPath).resolvingSymlinksInPath().standardizedFileURL.path
            return normalizedEntry == normalizedProtected
        }
        try? saveHistory(remaining)
        return removed
    }

    /// Total bytes occupied by downloaded wallpapers.
    public func totalCacheBytes() -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: wallpapersDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return files.reduce(Int64(0)) { partial, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }
}
