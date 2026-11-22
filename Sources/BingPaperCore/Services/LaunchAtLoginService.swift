import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: String, Sendable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable

    public var label: String {
        switch self {
        case .enabled: "Enabled"
        case .requiresApproval: "Needs Approval in System Settings"
        case .disabled: "Off"
        case .unavailable: "Available when run as BingPaper.app"
        }
    }
}

public struct LaunchAtLoginService: Sendable {
    public init() {}

    public var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    public func currentStatus() -> LaunchAtLoginStatus {
        guard isRunningFromAppBundle else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
