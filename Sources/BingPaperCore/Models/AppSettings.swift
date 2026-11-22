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

public struct AppSettings: Codable, Sendable, Equatable {
    public var market: BingMarket
    public var preferUHD: Bool
    public var scalingMode: WallpaperScalingMode
    public var syncAllSpacesAndLockScreen: Bool
    public var dailyUpdateEnabled: Bool
    public var updateHour: Int
    public var updateMinute: Int
    public var retentionDays: Int
    public var sendNotifications: Bool
    public var reapplyOnDisplayChange: Bool

    public init(
        market: BingMarket = .auto,
        preferUHD: Bool = true,
        scalingMode: WallpaperScalingMode = .fillScreen,
        syncAllSpacesAndLockScreen: Bool = true,
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
        self.syncAllSpacesAndLockScreen = syncAllSpacesAndLockScreen
        self.dailyUpdateEnabled = dailyUpdateEnabled
        self.updateHour = max(0, min(23, updateHour))
        self.updateMinute = max(0, min(59, updateMinute))
        self.retentionDays = max(1, retentionDays)
        self.sendNotifications = sendNotifications
        self.reapplyOnDisplayChange = reapplyOnDisplayChange
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
