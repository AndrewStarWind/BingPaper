import AppKit
import BingPaperCore
import Foundation
import Network
import Observation

enum SettingsTab: Hashable {
    case general
    case wallpaper
    case storage
    case about
}

@MainActor
@Observable
final class WallpaperViewModel {
    private static let lastUpdateKey = "com.bingpaper.state.lastSuccessfulUpdate"
    private static let lastBingDateKey = "com.bingpaper.state.lastAppliedBingStartDate"
    private static let lastAppliedPathKey = "com.bingpaper.state.lastAppliedPath"

    var settings: AppSettings {
        didSet {
            settings.save()
            handleSettingsChange(from: oldValue, to: settings)
        }
    }

    var selectedSettingsTab: SettingsTab = .general
    var recentImages: [BingImageMetadata] = []
    var selectedIndex: Int = 0
    var history: [WallpaperHistoryEntry] = []
    var currentEntry: WallpaperHistoryEntry?
    var lastApplyReport: WallpaperApplyReport?
    var systemCheckReport: SystemCheckReport = SystemCheckReport(items: [])

    var isUpdating: Bool = false
    var statusMessage: String = "Ready"
    var errorMessage: String?
    var lastSuccessfulUpdate: Date?
    var lastAppliedBingStartDate: String?
    var nextScheduledUpdate: Date?
    var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    var cacheSizeText: String = "0 MB"
    var connectedScreenCount: Int = NSScreen.screens.count

    private let apiClient: BingAPIClient
    private let store: WallpaperStore
    private let applier: WallpaperApplier
    private let scheduler: DailyScheduler
    private let launchService: LaunchAtLoginService
    private let systemCheckService: SystemCheckService
    private let notifications: NotificationService

    private var scheduleTask: Task<Void, Never>?
    private var displayDebounceTask: Task<Void, Never>?
    private var spaceDebounceTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var dayChangeObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var wasOffline: Bool = false
    private var hasBootstrapped: Bool = false

    init(
        apiClient: BingAPIClient = BingAPIClient(),
        store: WallpaperStore = WallpaperStore(),
        applier: WallpaperApplier = WallpaperApplier(),
        scheduler: DailyScheduler = DailyScheduler(),
        launchService: LaunchAtLoginService = LaunchAtLoginService(),
        systemCheckService: SystemCheckService = SystemCheckService(),
        notifications: NotificationService = NotificationService()
    ) {
        self.apiClient = apiClient
        self.store = store
        self.applier = applier
        self.scheduler = scheduler
        self.launchService = launchService
        self.systemCheckService = systemCheckService
        self.notifications = notifications
        self.settings = AppSettings.load()

        loadPersistedState()
        refreshCacheSize()
        refreshLaunchAtLoginStatus()
        runSystemChecks()
    }

    /// Combines the latest 8 days from Bing with any older downloaded days from local history, newest first.
    var browsableWallpapers: [BingImageMetadata] {
        var seen = Set<String>()
        var combined: [BingImageMetadata] = []

        for item in recentImages {
            if seen.insert(item.startdate).inserted {
                combined.append(item)
            }
        }
        let sortedHistory = history.sorted { $0.metadata.startdate > $1.metadata.startdate }
        for entry in sortedHistory {
            if seen.insert(entry.metadata.startdate).inserted {
                combined.append(entry.metadata)
            }
        }
        return combined
    }

    var selectedMetadata: BingImageMetadata? {
        let items = browsableWallpapers
        guard items.indices.contains(selectedIndex) else {
            return currentEntry?.metadata
        }
        return items[selectedIndex]
    }

    var selectedLocalImageURL: URL? {
        guard let meta = selectedMetadata else {
            return currentEntry?.fileURL
        }
        let market = settings.market.resolvedMarketCode()
        if let existing = store.existingFileURL(for: meta, market: market, preferUHD: settings.preferUHD) {
            return existing
        }
        if let match = history.first(where: { $0.metadata.startdate == meta.startdate && FileManager.default.fileExists(atPath: $0.localPath) }) {
            return match.fileURL
        }
        return nil
    }

    var isSelectedCurrentlyApplied: Bool {
        guard let selected = selectedMetadata, let current = currentEntry else { return false }
        return selected.startdate == current.metadata.startdate && selected.urlbase == current.metadata.urlbase
    }

    var canGoOlder: Bool {
        selectedIndex + 1 < browsableWallpapers.count
    }

    var canGoNewer: Bool {
        selectedIndex > 0
    }

    func selectDay(at index: Int) {
        let items = browsableWallpapers
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func runSystemChecks() {
        refreshLaunchAtLoginStatus()
        connectedScreenCount = NSScreen.screens.count
        systemCheckReport = systemCheckService.runLiveCheck(
            settings: settings,
            launchStatus: launchAtLoginStatus
        )
    }

    func performCheckFix(_ action: CheckFixAction) {
        switch action {
        case .enableLaunchAtLogin:
            toggleLaunchAtLogin(true)
        case .openLoginItemsSettings:
            openLoginItemsSettings()
        case .enableDailySchedule:
            settings.dailyUpdateEnabled = true
        case .enableLockScreenSync:
            settings.wallpaperTarget = .allScreensAndLockScreen
        case .openWallpaperSettings:
            openWallpaperSystemSettings()
        }
        runSystemChecks()
    }

    func openWallpaperSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        setupObservers()
        setupNetworkMonitor()
        rescheduleDailyTimer()

        Task {
            if settings.sendNotifications {
                await notifications.requestAuthorizationIfNeeded()
            }
            await refreshArchiveSilently()
            if settings.dailyUpdateEnabled && isDailyUpdateDue() {
                await updateToToday(force: false, trigger: "Launch")
            }
        }
    }

    func selectOlder() {
        if canGoOlder {
            selectedIndex += 1
        }
    }

    func selectNewer() {
        if canGoNewer {
            selectedIndex -= 1
        }
    }

    func selectToday() {
        selectedIndex = 0
    }

    /// Fetches today's Bing archive and applies today's wallpaper across all displays, Spaces, and Lock Screen.
    func updateToToday(force: Bool = true, trigger: String = "Manual") async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        statusMessage = "Fetching Bing daily image…"
        defer {
            isUpdating = false
            rescheduleDailyTimer()
        }

        let market = settings.market.resolvedMarketCode()
        do {
            let images = try await apiClient.fetchArchive(daysAgo: 0, count: 8, market: market)
            recentImages = images
            selectedIndex = 0

            guard let today = images.first else {
                throw BingAPIError.emptyArchive
            }

            if !force,
               let lastStart = lastAppliedBingStartDate,
               lastStart == today.startdate,
               let current = currentEntry,
               current.market == market,
               FileManager.default.fileExists(atPath: current.localPath) {
                statusMessage = "Already up to date"
                persistLastUpdate(date: Date(), bingStartDate: today.startdate, path: current.localPath)
                return
            }

            try await downloadAndApply(metadata: today, market: market, trigger: trigger)
        } catch {
            BingPaperLog.app.error("Update failed (\(trigger)): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            statusMessage = "Update failed"
        }
    }

    /// Downloads (if needed) and applies a specific Bing image from the recent 8-day archive.
    func applySelectedMetadata() async {
        guard let metadata = selectedMetadata else {
            await updateToToday(force: true, trigger: "Manual")
            return
        }
        await applyMetadata(metadata, trigger: "Manual")
    }

    func applyMetadata(_ metadata: BingImageMetadata, trigger: String = "Manual") async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        let market = settings.market.resolvedMarketCode()
        do {
            try await downloadAndApply(metadata: metadata, market: market, trigger: trigger)
        } catch {
            BingPaperLog.app.error("Apply failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            statusMessage = "Could not apply wallpaper"
        }
    }

    func applyHistoryEntry(_ entry: WallpaperHistoryEntry) async {
        guard !isUpdating else { return }
        guard FileManager.default.fileExists(atPath: entry.localPath) else {
            errorMessage = "That cached image file is no longer on disk."
            history = store.loadHistory()
            return
        }

        isUpdating = true
        errorMessage = nil
        statusMessage = "Applying wallpaper…"
        defer { isUpdating = false }

        do {
            let report = try await applier.applyWallpaper(
                at: entry.fileURL,
                scalingMode: settings.scalingMode,
                target: settings.wallpaperTarget,
                backupDirectory: store.backupsDirectory
            )
            let now = Date()
            try? store.markApplied(entryID: entry.id, at: now)
            history = store.loadHistory()
            currentEntry = history.first(where: { $0.id == entry.id }) ?? entry
            lastApplyReport = report
            persistLastUpdate(date: now, bingStartDate: entry.metadata.startdate, path: entry.localPath)
            statusMessage = summaryStatus(from: report)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Failed to apply wallpaper"
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchService.setEnabled(enabled)
            refreshLaunchAtLoginStatus()
        } catch {
            errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
            refreshLaunchAtLoginStatus()
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchService.currentStatus()
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openWallpapersFolder() {
        try? store.ensureDirectoriesExist()
        NSWorkspace.shared.open(store.wallpapersDirectory)
    }

    func revealCurrentInFinder() {
        if let url = currentEntry?.fileURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            openWallpapersFolder()
        }
    }

    func saveCopyOfMetadata(_ metadata: BingImageMetadata) async {
        let market = settings.market.resolvedMarketCode()
        var sourceURL = store.existingFileURL(for: metadata, market: market, preferUHD: settings.preferUHD)

        if sourceURL == nil {
            do {
                let (data, _) = try await apiClient.downloadImageData(for: metadata, preferUHD: settings.preferUHD)
                let entry = try store.saveImage(data, metadata: metadata, market: market, preferUHD: settings.preferUHD)
                history = store.loadHistory()
                refreshCacheSize()
                sourceURL = entry.fileURL
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        guard let sourceURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(metadata.startdate)-\(metadata.displayTitle.replacingOccurrences(of: "/", with: "-")).jpg"
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: sourceURL, to: dest)
            } catch {
                errorMessage = "Could not save copy: \(error.localizedDescription)"
            }
        }
    }

    func clearCache() {
        do {
            let removed = try store.clearCache(keeping: currentEntry?.localPath)
            history = store.loadHistory()
            refreshCacheSize()
            statusMessage = "Cleared \(removed) cached image(s)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCacheSize() {
        let bytes = store.totalCacheBytes()
        cacheSizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Internals

    private func downloadAndApply(metadata: BingImageMetadata, market: String, trigger: String) async throws {
        let entry: WallpaperHistoryEntry
        if let existing = store.existingFileURL(for: metadata, market: market, preferUHD: settings.preferUHD) {
            statusMessage = "Applying wallpaper…"
            let existingHistory = store.loadHistory()
            if let match = existingHistory.first(where: { $0.localPath == existing.path }) {
                entry = match
            } else {
                let data = try Data(contentsOf: existing)
                entry = try store.saveImage(data, metadata: metadata, market: market, preferUHD: settings.preferUHD)
            }
        } else {
            statusMessage = settings.preferUHD ? "Downloading 4K UHD wallpaper…" : "Downloading HD wallpaper…"
            let (data, _) = try await apiClient.downloadImageData(for: metadata, preferUHD: settings.preferUHD)
            entry = try store.saveImage(data, metadata: metadata, market: market, preferUHD: settings.preferUHD)
        }

        statusMessage = switch settings.wallpaperTarget {
        case .allScreensAndLockScreen: "Updating all screens & Lock Screen…"
        case .screensAndSpacesOnly: "Updating screens & Spaces…"
        case .lockScreenOnly: "Updating Lock Screen…"
        }

        let report = try await applier.applyWallpaper(
            at: entry.fileURL,
            scalingMode: settings.scalingMode,
            target: settings.wallpaperTarget,
            backupDirectory: store.backupsDirectory
        )

        let now = Date()
        try? store.markApplied(entryID: entry.id, at: now)
        _ = try? store.pruneOldWallpapers(retentionDays: settings.retentionDays, keeping: entry.localPath, now: now)

        history = store.loadHistory()
        currentEntry = history.first(where: { $0.id == entry.id }) ?? entry
        lastApplyReport = report
        connectedScreenCount = report.screensUpdated
        persistLastUpdate(date: now, bingStartDate: metadata.startdate, path: entry.localPath)
        refreshCacheSize()

        statusMessage = summaryStatus(from: report)
        if let warning = report.warningMessage {
            errorMessage = "Active screens updated; Lock Screen sync note: \(warning)"
        }

        if settings.sendNotifications && trigger != "DisplayChange" {
            await notifications.notifyWallpaperUpdated(metadata: metadata, report: report)
        }
    }

    private func refreshArchiveSilently() async {
        let market = settings.market.resolvedMarketCode()
        if let images = try? await apiClient.fetchArchive(daysAgo: 0, count: 8, market: market) {
            recentImages = images
        }
    }

    private func summaryStatus(from report: WallpaperApplyReport) -> String {
        let displayWord = report.screensUpdated == 1 ? "display" : "displays"
        switch report.target {
        case .allScreensAndLockScreen:
            return "\(report.screensUpdated) \(displayWord), all Spaces & Lock Screen synced"
        case .screensAndSpacesOnly:
            return "\(report.screensUpdated) \(displayWord) & all Spaces synced"
        case .lockScreenOnly:
            return "Lock Screen updated"
        }
    }

    private func isDailyUpdateDue(now: Date = Date()) -> Bool {
        scheduler.isUpdateDue(
            lastSuccessfulUpdate: lastSuccessfulUpdate,
            lastAppliedBingStartDate: lastAppliedBingStartDate,
            scheduledHour: settings.updateHour,
            scheduledMinute: settings.updateMinute,
            now: now
        )
    }

    private func rescheduleDailyTimer() {
        scheduleTask?.cancel()
        guard settings.dailyUpdateEnabled else {
            nextScheduledUpdate = nil
            return
        }

        let target = scheduler.nextScheduledDate(
            hour: settings.updateHour,
            minute: settings.updateMinute,
            after: Date()
        )
        nextScheduledUpdate = target

        scheduleTask = Task { [weak self] in
            let interval = max(5, target.timeIntervalSinceNow)
            BingPaperLog.scheduler.info("Next daily update scheduled in \(Int(interval))s at \(target.formatted())")
            do {
                try await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await self.updateToToday(force: false, trigger: "ScheduledDaily")
            } catch {
                // Task cancelled on reschedule or shutdown.
            }
        }
    }

    private func setupObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                BingPaperLog.scheduler.info("System woke from sleep; checking daily wallpaper schedule.")
                if self.settings.dailyUpdateEnabled && self.isDailyUpdateDue() {
                    await self.updateToToday(force: false, trigger: "Wake")
                } else {
                    self.rescheduleDailyTimer()
                }
            }
        }

        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                BingPaperLog.scheduler.info("Calendar day changed; checking daily wallpaper schedule.")
                if self.settings.dailyUpdateEnabled && self.isDailyUpdateDue() {
                    await self.updateToToday(force: false, trigger: "DayChange")
                } else {
                    self.rescheduleDailyTimer()
                }
            }
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let newCount = NSScreen.screens.count
                self.connectedScreenCount = newCount
                guard self.settings.reapplyOnDisplayChange,
                      let current = self.currentEntry,
                      FileManager.default.fileExists(atPath: current.localPath) else {
                    return
                }
                self.displayDebounceTask?.cancel()
                self.displayDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    BingPaperLog.wallpaper.info("Display configuration changed (\(newCount) screen(s)); re-applying wallpaper.")
                    _ = try? await self.applier.applyWallpaper(
                        at: current.fileURL,
                        scalingMode: self.settings.scalingMode,
                        target: self.settings.wallpaperTarget,
                        backupDirectory: self.store.backupsDirectory
                    )
                }
            }
        }

        spaceChangeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      !self.isUpdating,
                      self.settings.wallpaperTarget != .lockScreenOnly,
                      let current = self.currentEntry,
                      FileManager.default.fileExists(atPath: current.localPath) else {
                    return
                }
                self.spaceDebounceTask?.cancel()
                self.spaceDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, !self.isUpdating else { return }
                    _ = self.applier.syncActiveSpaceIfNeeded(
                        to: current.fileURL,
                        scalingMode: self.settings.scalingMode
                    )
                }
            }
        }
    }

    private func setupNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied {
                    if self.wasOffline && self.settings.dailyUpdateEnabled && self.isDailyUpdateDue() {
                        BingPaperLog.scheduler.info("Network reconnected; retrying pending daily wallpaper update.")
                        await self.updateToToday(force: false, trigger: "NetworkReconnect")
                    }
                    self.wasOffline = false
                } else {
                    self.wasOffline = true
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bingpaper.network", qos: .utility))
        self.pathMonitor = monitor
    }

    private func handleSettingsChange(from old: AppSettings, to new: AppSettings) {
        runSystemChecks()

        if old.dailyUpdateEnabled != new.dailyUpdateEnabled
            || old.updateHour != new.updateHour
            || old.updateMinute != new.updateMinute {
            rescheduleDailyTimer()
        }

        if old.market != new.market || old.preferUHD != new.preferUHD {
            Task {
                await refreshArchiveSilently()
            }
        }

        if (old.scalingMode != new.scalingMode || old.wallpaperTarget != new.wallpaperTarget),
           let current = currentEntry {
            Task {
                await applyHistoryEntry(current)
            }
        }

        if !old.sendNotifications && new.sendNotifications {
            Task {
                await notifications.requestAuthorizationIfNeeded()
            }
        }
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        if let timestamp = defaults.object(forKey: Self.lastUpdateKey) as? Date {
            lastSuccessfulUpdate = timestamp
        }
        lastAppliedBingStartDate = defaults.string(forKey: Self.lastBingDateKey)
        history = store.loadHistory()

        if let savedPath = defaults.string(forKey: Self.lastAppliedPathKey),
           let match = history.first(where: { $0.localPath == savedPath }) {
            currentEntry = match
        } else {
            currentEntry = history.first
        }
    }

    private func persistLastUpdate(date: Date, bingStartDate: String, path: String) {
        lastSuccessfulUpdate = date
        lastAppliedBingStartDate = bingStartDate
        let defaults = UserDefaults.standard
        defaults.set(date, forKey: Self.lastUpdateKey)
        defaults.set(bingStartDate, forKey: Self.lastBingDateKey)
        defaults.set(path, forKey: Self.lastAppliedPathKey)
    }
}
