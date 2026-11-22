import BingPaperCore
import Foundation
import Testing

@Suite("WallpaperStore")
struct WallpaperStoreTests {
    @Test("Saves image, records history, and prunes old files while protecting active wallpaper")
    func savesAndPrunesSafely() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingPaperStoreTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WallpaperStore(baseDirectory: tempDir)
        let sampleBytes = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(0xAA), count: 2048))

        let oldMeta = BingImageMetadata(
            startdate: "20260901",
            url: "/th?id=OHR.Old_1920x1080.jpg",
            urlbase: "/th?id=OHR.Old",
            copyright: "Old Photo",
            hsh: "11111111"
        )
        let activeMeta = BingImageMetadata(
            startdate: "20261122",
            url: "/th?id=OHR.Active_1920x1080.jpg",
            urlbase: "/th?id=OHR.Active",
            copyright: "Active Photo",
            hsh: "22222222"
        )

        let oldEntry = try store.saveImage(sampleBytes, metadata: oldMeta, market: "en-US", preferUHD: true)
        let activeEntry = try store.saveImage(sampleBytes, metadata: activeMeta, market: "en-US", preferUHD: true)

        // Backdate both files by 60 days so only the protected active one survives pruning.
        let sixtyDaysAgo = Date().addingTimeInterval(-60 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: oldEntry.localPath)
        try FileManager.default.setAttributes([.modificationDate: sixtyDaysAgo], ofItemAtPath: activeEntry.localPath)

        let removed = try store.pruneOldWallpapers(retentionDays: 30, keeping: activeEntry.localPath)

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: oldEntry.localPath))
        #expect(FileManager.default.fileExists(atPath: activeEntry.localPath))
        #expect(store.loadHistory().map(\.id) == [activeEntry.id])
    }
}
