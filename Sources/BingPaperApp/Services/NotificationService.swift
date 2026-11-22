import BingPaperCore
import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var isBundleSupported: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app" && Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorizationIfNeeded() async {
        guard isBundleSupported else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notifyWallpaperUpdated(metadata: BingImageMetadata, report: WallpaperApplyReport) async {
        guard isBundleSupported else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "BingPaper Updated"
        content.subtitle = metadata.displayTitle
        if report.allSpacesAndLockScreenSynced {
            content.body = "Applied to \(report.screensUpdated) display(s), all Spaces, and Lock Screen."
        } else {
            content.body = "Applied to \(report.screensUpdated) active display(s)."
        }

        let request = UNNotificationRequest(
            identifier: "com.bingpaper.updated.\(metadata.startdate)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
