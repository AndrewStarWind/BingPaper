import Foundation

public enum WallpaperScalingMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case fillScreen = "fill"
    case fitToScreen = "fit"
    case stretchToFill = "stretch"
    case center = "center"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fillScreen: "Fill Screen (Recommended)"
        case .fitToScreen: "Fit to Screen"
        case .stretchToFill: "Stretch to Fill"
        case .center: "Center"
        }
    }
}

public enum WallpaperTarget: String, CaseIterable, Codable, Sendable, Identifiable {
    case allScreensAndLockScreen = "all"
    case screensAndSpacesOnly = "screensAndSpaces"
    case lockScreenOnly = "lockScreen"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allScreensAndLockScreen:
            "All Screens, Spaces & Lock Screen"
        case .screensAndSpacesOnly:
            "Screens & Spaces Only"
        case .lockScreenOnly:
            "Lock Screen Only"
        }
    }

    public var descriptionText: String {
        switch self {
        case .allScreensAndLockScreen:
            "Updates every connected display, all Spaces (active and inactive), and the Lock Screen. Note: When FileVault is enabled, macOS protects the pre-boot unlock screen until first login."
        case .screensAndSpacesOnly:
            "Updates every connected display and Space without modifying your Lock Screen / Screen Saver configuration."
        case .lockScreenOnly:
            "Updates only the Lock Screen / Screen Saver background while keeping your current Desktop wallpapers unchanged. Note: When FileVault is enabled, macOS protects the pre-boot unlock screen until first login."
        }
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var market: BingMarket
    public var preferUHD: Bool
    public var scalingMode: WallpaperScalingMode
    public var wallpaperTarget: WallpaperTarget
    public var dailyUpdateEnabled: Bool
    public var updateHour: Int
    public var updateMinute: Int
    public var retentionDays: Int
    public var sendNotifications: Bool
    public var reapplyOnDisplayChange: Bool

    /// Convenience alias preserved for callers/tests checking whether Lock Screen is included.
    public var includesLockScreen: Bool {
        wallpaperTarget == .allScreensAndLockScreen || wallpaperTarget == .lockScreenOnly
    }

    public init(
        market: BingMarket = .auto,
        preferUHD: Bool = true,
        scalingMode: WallpaperScalingMode = .fillScreen,
        wallpaperTarget: WallpaperTarget = .allScreensAndLockScreen,
        dailyUpdateEnabled: Bool = true,
        updateHour: Int = 9,
        updateMinute: Int = 0,
        retentionDays: Int = 30,
        sendNotifications: Bool = true,
        reapplyOnDisplayChange: Bool = true
    ) {
        self.market = market
        self.preferUHD = preferUHD
        self.scalingMode = scalingMode
        self.wallpaperTarget = wallpaperTarget
        self.dailyUpdateEnabled = dailyUpdateEnabled
        self.updateHour = max(0, min(23, updateHour))
        self.updateMinute = max(0, min(59, updateMinute))
        self.retentionDays = max(1, retentionDays)
        self.sendNotifications = sendNotifications
        self.reapplyOnDisplayChange = reapplyOnDisplayChange
    }

    private enum CodingKeys: String, CodingKey {
        case market
        case preferUHD
        case scalingMode
        case wallpaperTarget
        case syncAllSpacesAndLockScreen // legacy migration key
        case dailyUpdateEnabled
        case updateHour
        case updateMinute
        case retentionDays
        case sendNotifications
        case reapplyOnDisplayChange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.market = try container.decodeIfPresent(BingMarket.self, forKey: .market) ?? .auto
        self.preferUHD = try container.decodeIfPresent(Bool.self, forKey: .preferUHD) ?? true
        self.scalingMode = try container.decodeIfPresent(WallpaperScalingMode.self, forKey: .scalingMode) ?? .fillScreen

        if let target = try container.decodeIfPresent(WallpaperTarget.self, forKey: .wallpaperTarget) {
            self.wallpaperTarget = target
        } else if let legacySync = try container.decodeIfPresent(Bool.self, forKey: .syncAllSpacesAndLockScreen) {
            self.wallpaperTarget = legacySync ? .allScreensAndLockScreen : .screensAndSpacesOnly
        } else {
            self.wallpaperTarget = .allScreensAndLockScreen
        }

        self.dailyUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyUpdateEnabled) ?? true
        let hour = try container.decodeIfPresent(Int.self, forKey: .updateHour) ?? 9
        let minute = try container.decodeIfPresent(Int.self, forKey: .updateMinute) ?? 0
        self.updateHour = max(0, min(23, hour))
        self.updateMinute = max(0, min(59, minute))
        self.retentionDays = max(1, try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30)
        self.sendNotifications = try container.decodeIfPresent(Bool.self, forKey: .sendNotifications) ?? true
        self.reapplyOnDisplayChange = try container.decodeIfPresent(Bool.self, forKey: .reapplyOnDisplayChange) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(market, forKey: .market)
        try container.encode(preferUHD, forKey: .preferUHD)
        try container.encode(scalingMode, forKey: .scalingMode)
        try container.encode(wallpaperTarget, forKey: .wallpaperTarget)
        try container.encode(dailyUpdateEnabled, forKey: .dailyUpdateEnabled)
        try container.encode(updateHour, forKey: .updateHour)
        try container.encode(updateMinute, forKey: .updateMinute)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(sendNotifications, forKey: .sendNotifications)
        try container.encode(reapplyOnDisplayChange, forKey: .reapplyOnDisplayChange)
    }

    public static let defaultsKey = "com.bingpaper.app.settings.v1"

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
