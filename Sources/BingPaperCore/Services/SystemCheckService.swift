import AppKit
import Foundation

public enum CheckSeverity: String, Sendable, Equatable {
    case ok
    case warning
    case actionRequired
}

public enum CheckFixAction: String, Sendable, Equatable {
    case enableLaunchAtLogin
    case openLoginItemsSettings
    case enableDailySchedule
    case enableLockScreenSync
    case openWallpaperSettings
}

public struct SystemCheckItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: CheckSeverity
    public let fixAction: CheckFixAction?
    public let fixLabel: String?

    public init(
        id: String,
        title: String,
        detail: String,
        severity: CheckSeverity,
        fixAction: CheckFixAction? = nil,
        fixLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.fixAction = fixAction
        self.fixLabel = fixLabel
    }
}

public struct SystemCheckReport: Sendable, Equatable {
    public let items: [SystemCheckItem]
    public let checkedAt: Date

    public var issueCount: Int {
        items.filter { $0.severity != .ok }.count
    }

    public var allChecksPassed: Bool {
        issueCount == 0
    }

    public init(items: [SystemCheckItem], checkedAt: Date = Date()) {
        self.items = items
        self.checkedAt = checkedAt
    }
}

/// Evaluates all settings and macOS prerequisites needed for reliable daily multi-display + Lock Screen updates.
public struct SystemCheckService: Sendable {
    public init() {}

    @MainActor
    public func runLiveCheck(
        settings: AppSettings,
        launchStatus: LaunchAtLoginStatus,
        indexURL: URL = WallpaperIndexUpdater.defaultIndexURL
    ) -> SystemCheckReport {
        let screens = NSScreen.screens
        let screenNames = screens.map(\.localizedName)
        return evaluate(
            settings: settings,
            launchStatus: launchStatus,
            screenNames: screenNames,
            indexURL: indexURL
        )
    }

    public func evaluate(
        settings: AppSettings,
        launchStatus: LaunchAtLoginStatus,
        screenNames: [String],
        indexURL: URL = WallpaperIndexUpdater.defaultIndexURL,
        now: Date = Date()
    ) -> SystemCheckReport {
        var items: [SystemCheckItem] = []

        // 1. Connected displays
        if screenNames.isEmpty {
            items.append(SystemCheckItem(
                id: "displays",
                title: "Connected Displays",
                detail: "No active displays detected.",
                severity: .warning
            ))
        } else {
            let names = screenNames.joined(separator: ", ")
            items.append(SystemCheckItem(
                id: "displays",
                title: "Connected Displays (\(screenNames.count))",
                detail: names,
                severity: .ok
            ))
        }

        // 2. macOS Wallpaper Store (Index.plist) access for all Spaces & Lock Screen
        let fm = FileManager.default
        let indexPath = indexURL.path
        if !fm.fileExists(atPath: indexPath) {
            items.append(SystemCheckItem(
                id: "wallpaper-store",
                title: "macOS Wallpaper Store (Lock Screen & Spaces)",
                detail: "Index.plist was not found yet. Open System Settings → Wallpaper once or apply a wallpaper to initialize it.",
                severity: .warning,
                fixAction: .openWallpaperSettings,
                fixLabel: "Open Wallpaper Settings"
            ))
        } else if !fm.isReadableFile(atPath: indexPath) || !fm.isWritableFile(atPath: indexPath) {
            items.append(SystemCheckItem(
                id: "wallpaper-store",
                title: "macOS Wallpaper Store (Lock Screen & Spaces)",
                detail: "Index.plist is not writable. Run BingPaper.app outside any restrictive sandbox so Lock Screen and inactive Spaces can sync.",
                severity: .actionRequired,
                fixAction: .openWallpaperSettings,
                fixLabel: "Open Wallpaper Settings"
            ))
        } else {
            items.append(SystemCheckItem(
                id: "wallpaper-store",
                title: "macOS Wallpaper Store (Lock Screen & Spaces)",
                detail: "Index.plist is accessible and writable for all-Spaces & Lock Screen synchronization.",
                severity: .ok
            ))
        }

        // 3. Selected wallpaper target
        items.append(SystemCheckItem(
            id: "wallpaper-target",
            title: "Wallpaper Target: \(settings.wallpaperTarget.displayName)",
            detail: settings.wallpaperTarget.descriptionText,
            severity: .ok
        ))

        // 4. Daily Schedule setting
        if settings.dailyUpdateEnabled {
            let timeStr = String(format: "%02d:%02d", settings.updateHour, settings.updateMinute)
            items.append(SystemCheckItem(
                id: "daily-schedule",
                title: "Automatic Daily Update",
                detail: "Scheduled daily at \(timeStr) (with automatic catch-up on launch, wake, and reconnect).",
                severity: .ok
            ))
        } else {
            items.append(SystemCheckItem(
                id: "daily-schedule",
                title: "Automatic Daily Update",
                detail: "Paused — wallpapers will only change when you update manually.",
                severity: .warning,
                fixAction: .enableDailySchedule,
                fixLabel: "Enable Daily Updates"
            ))
        }

        // 5. Launch at Login
        switch launchStatus {
        case .enabled:
            items.append(SystemCheckItem(
                id: "launch-at-login",
                title: "Launch at Login",
                detail: "Enabled — BingPaper starts automatically so daily updates run after restarts.",
                severity: .ok
            ))
        case .requiresApproval:
            items.append(SystemCheckItem(
                id: "launch-at-login",
                title: "Launch at Login",
                detail: "Registered, awaiting approval in System Settings → General → Login Items.",
                severity: .actionRequired,
                fixAction: .openLoginItemsSettings,
                fixLabel: "Open Login Items"
            ))
        case .disabled:
            items.append(SystemCheckItem(
                id: "launch-at-login",
                title: "Launch at Login",
                detail: "Off — enable so BingPaper keeps updating every day automatically after reboot.",
                severity: .warning,
                fixAction: .enableLaunchAtLogin,
                fixLabel: "Enable Launch at Login"
            ))
        case .unavailable:
            items.append(SystemCheckItem(
                id: "launch-at-login",
                title: "Launch at Login",
                detail: "Launch BingPaper.app (built via Scripts/build-app.sh) to register as a macOS Login Item.",
                severity: .warning
            ))
        }

        return SystemCheckReport(items: items, checkedAt: now)
    }
}
