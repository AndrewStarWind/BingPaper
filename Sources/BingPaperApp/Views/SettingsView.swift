import AppKit
import BingPaperCore
import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: WallpaperViewModel

    private var scheduledTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = viewModel.settings.updateHour
                components.minute = viewModel.settings.updateMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                viewModel.settings.updateHour = comps.hour ?? 9
                viewModel.settings.updateMinute = comps.minute ?? 0
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.launchAtLoginStatus == .enabled },
            set: { viewModel.toggleLaunchAtLogin($0) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch viewModel.selectedSettingsTab {
                case .general:
                    generalTab
                case .wallpaper:
                    wallpaperTab
                case .storage:
                    storageTab
                case .about:
                    aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 420)
        .onAppear {
            viewModel.runSystemChecks()
            viewModel.refreshCacheSize()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.general, title: "General", systemImage: "gearshape")
            tabButton(.wallpaper, title: "Wallpaper", systemImage: "display.2")
            tabButton(.storage, title: "Storage", systemImage: "internaldrive")
            tabButton(.about, title: "About", systemImage: "info.circle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tabButton(
        _ tab: SettingsTab,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = viewModel.selectedSettingsTab == tab
        Button {
            viewModel.selectedSettingsTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch BingPaper at Login", isOn: launchAtLoginBinding)
                    .disabled(viewModel.launchAtLoginStatus == .unavailable)

                HStack {
                    Text("Login Item Status")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.launchAtLoginStatus.label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if viewModel.launchAtLoginStatus == .requiresApproval {
                    Button("Open System Settings → Login Items") {
                        viewModel.openLoginItemsSettings()
                    }
                }
            }

            Section("Daily Schedule") {
                Toggle("Automatically update wallpaper every day", isOn: $viewModel.settings.dailyUpdateEnabled)

                DatePicker(
                    "Daily check time",
                    selection: scheduledTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!viewModel.settings.dailyUpdateEnabled)

                Text("If your Mac is asleep or offline at the scheduled time, BingPaper automatically updates as soon as it wakes or reconnects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Show notification when wallpaper updates", isOn: $viewModel.settings.sendNotifications)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Wallpaper & Lock Screen Tab

    private var wallpaperTab: some View {
        Form {
            Section("Bing Daily Image") {
                Picker("Region / Market", selection: $viewModel.settings.market) {
                    ForEach(BingMarket.allCases) { market in
                        Text(market.displayName).tag(market)
                    }
                }

                Toggle("Download 4K UHD resolution when available", isOn: $viewModel.settings.preferUHD)

                Picker("Image Scaling", selection: $viewModel.settings.scalingMode) {
                    ForEach(WallpaperScalingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Apply To") {
                Picker("Target", selection: $viewModel.settings.wallpaperTarget) {
                    ForEach(WallpaperTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }

                Toggle("Re-apply automatically when monitors are connected", isOn: $viewModel.settings.reapplyOnDisplayChange)

                Text(viewModel.settings.wallpaperTarget.descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        Form {
            Section("Wallpaper Archive") {
                Picker("Keep downloaded wallpapers for", selection: $viewModel.settings.retentionDays) {
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                    Text("90 Days").tag(90)
                    Text("1 Year").tag(365)
                }

                LabeledContent("Cached Wallpapers", value: "\(viewModel.history.count) image(s)")
                LabeledContent("Disk Usage", value: viewModel.cacheSizeText)
            }

            Section("Actions") {
                HStack {
                    Button("Open Wallpapers Folder") {
                        viewModel.openWallpapersFolder()
                    }
                    Spacer()
                    Button("Clear Cached Wallpapers", role: .destructive) {
                        viewModel.clearCache()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }

            VStack(spacing: 4) {
                Text("BingPaper")
                    .font(.title2.bold())
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Automatically updates your macOS wallpapers every day across every display, every Space, and the Lock Screen using Bing's 4K Daily Image.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let coffeeURL = URL(string: "https://buymeacoffee.com/sevasdreas") {
                Link(destination: coffeeURL) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
            }

            Spacer()

            Text("© \(currentYear) Andrey Ivanov")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}
