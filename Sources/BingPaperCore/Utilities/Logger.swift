import Foundation
import OSLog

public enum BingPaperLog {
    private static let subsystem = "com.bingpaper.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let wallpaper = Logger(subsystem: subsystem, category: "wallpaper")
    public static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    public static let store = Logger(subsystem: subsystem, category: "store")
}
