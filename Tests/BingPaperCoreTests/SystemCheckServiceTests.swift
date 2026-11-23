import BingPaperCore
import Foundation
import Testing

@Suite("SystemCheckService")
struct SystemCheckServiceTests {
    @Test("Reports all checks passed when settings, Index.plist, displays, and Login Item are configured")
    func passesWhenEverythingConfigured() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingPaperCheckTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeIndex = tempDir.appendingPathComponent("Index.plist")
        try Data("plist".utf8).write(to: fakeIndex)

        let service = SystemCheckService()
        let report = service.evaluate(
            settings: AppSettings(
                wallpaperTarget: .allScreensAndLockScreen,
                dailyUpdateEnabled: true,
                updateHour: 9,
                updateMinute: 0
            ),
            launchStatus: .enabled,
            screenNames: ["Built-in Retina Display", "Studio Display"],
            indexURL: fakeIndex
        )

        #expect(report.allChecksPassed == true)
        #expect(report.issueCount == 0)
        #expect(report.items.count == 5)
    }

    @Test("Flags missing Index.plist, disabled daily schedule, and off Login Item")
    func flagsMissingPrerequisites() {
        let missingIndex = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).plist")

        let service = SystemCheckService()
        let report = service.evaluate(
            settings: AppSettings(
                wallpaperTarget: .screensAndSpacesOnly,
                dailyUpdateEnabled: false
            ),
            launchStatus: .disabled,
            screenNames: ["Built-in Retina Display"],
            indexURL: missingIndex
        )

        #expect(report.allChecksPassed == false)
        #expect(report.issueCount == 3)
        #expect(report.items.contains { $0.id == "daily-schedule" && $0.fixAction == .enableDailySchedule })
        #expect(report.items.contains { $0.id == "launch-at-login" && $0.fixAction == .enableLaunchAtLogin })
    }

    @Test("Migrates legacy syncAllSpacesAndLockScreen setting into wallpaperTarget")
    func migratesLegacySettingsJSON() throws {
        let legacyFalseJSON = Data("""
        {
          "market": "en-US",
          "preferUHD": true,
          "scalingMode": "fill",
          "syncAllSpacesAndLockScreen": false,
          "dailyUpdateEnabled": true,
          "updateHour": 8,
          "updateMinute": 30,
          "retentionDays": 14,
          "sendNotifications": false,
          "reapplyOnDisplayChange": true
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyFalseJSON)
        #expect(decoded.wallpaperTarget == .screensAndSpacesOnly)
        #expect(decoded.updateHour == 8)
        #expect(decoded.updateMinute == 30)
    }
}
