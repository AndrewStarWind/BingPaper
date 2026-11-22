import AppKit
import BingPaperCore
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var viewModel: WallpaperViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            topBar
            heroPreview
            previousDaysStrip
            metadataSection
            primaryActions
            permissionAlertBanner

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 368)
        .onAppear {
            viewModel.runSystemChecks()
        }
    }

    // MARK: - Top Bar (Settings Left, Quit Right)

    private var topBar: some View {
        HStack {
            Button {
                openSettingsAndClosePopover()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Settings")
            .accessibilityLabel("Settings")

            Spacer()

            Text("BingPaper")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .help("Quit BingPaper")
            .accessibilityLabel("Quit BingPaper")
        }
    }

    private func openSettingsAndClosePopover() {
        viewModel.selectedSettingsTab = .general
        dismiss()
        for window in NSApp.windows where window.isVisible {
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("StatusBar") || window.level == .popUpMenu {
                window.orderOut(nil)
            }
        }
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Background Preview

    @ViewBuilder
    private var heroPreview: some View {
        ZStack {
            previewImage
                .frame(width: 340, height: 191)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )

            VStack {
                HStack {
                    GlassPillBadge(
                        text: dayBadgeTitle(for: viewModel.selectedIndex, metadata: viewModel.selectedMetadata),
                        systemImage: "calendar"
                    )
                    Spacer()
                    if viewModel.settings.preferUHD {
                        GlassPillBadge(text: "4K UHD", systemImage: "sparkles")
                    }
                }
                .padding(8)

                Spacer()

                HStack {
                    GlassIconButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "Previous day",
                        isDisabled: !viewModel.canGoOlder || viewModel.isUpdating
                    ) {
                        viewModel.selectOlder()
                    }

                    Spacer()

                    if viewModel.isSelectedCurrentlyApplied {
                        GlassPillBadge(text: "Active", systemImage: "checkmark.circle.fill", tint: .green)
                    } else {
                        Button {
                            Task {
                                if viewModel.selectedIndex == 0 {
                                    await viewModel.updateToToday(force: true, trigger: "PreviewButton")
                                } else {
                                    await viewModel.applySelectedMetadata()
                                }
                            }
                        } label: {
                            Label("Set as Background", systemImage: "display.2")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isUpdating)
                        .glassEffect(.regular.tint(Color.accentColor.opacity(0.45)).interactive(), in: Capsule())
                    }

                    Spacer()

                    GlassIconButton(
                        systemImage: "chevron.right",
                        accessibilityLabel: "Next day",
                        isDisabled: !viewModel.canGoNewer || viewModel.isUpdating
                    ) {
                        viewModel.selectNewer()
                    }
                }
                .padding(8)
            }
            .frame(width: 340, height: 191)

            if viewModel.isUpdating {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.35))
                    .frame(width: 340, height: 191)
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.regular)
                            Text(viewModel.statusMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
            }
        }
    }

    // MARK: - Previous Days Switcher Strip

    @ViewBuilder
    private var previousDaysStrip: some View {
        let items = viewModel.browsableWallpapers
        if items.count > 1 {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Previous Days")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(items.count - viewModel.selectedIndex) of \(items.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(items.enumerated()).reversed(), id: \.element.id) { index, item in
                                let isSelected = index == viewModel.selectedIndex
                                let isApplied = viewModel.currentEntry?.metadata.startdate == item.startdate

                                Button {
                                    viewModel.selectDay(at: index)
                                } label: {
                                    VStack(spacing: 3) {
                                        ZStack(alignment: .topTrailing) {
                                            miniThumbnail(for: item)
                                                .frame(width: 60, height: 34)
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .strokeBorder(
                                                            isSelected ? Color.accentColor : Color.white.opacity(0.15),
                                                            lineWidth: isSelected ? 2 : 0.75
                                                        )
                                                )

                                            if isApplied {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 7, height: 7)
                                                    .padding(3)
                                            }
                                        }

                                        Text(shortDayLabel(for: index, metadata: item))
                                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isUpdating)
                                .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .defaultScrollAnchor(.trailing)
                    .onAppear {
                        proxy.scrollTo(viewModel.selectedIndex, anchor: .trailing)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func miniThumbnail(for meta: BingImageMetadata) -> some View {
        if let entry = viewModel.history.first(where: { $0.metadata.startdate == meta.startdate && FileManager.default.fileExists(atPath: $0.localPath) }),
           let image = NSImage(contentsOf: entry.fileURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let previewURL = meta.imageURLs(preferUHD: false).first {
            AsyncImage(url: previewURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(.quaternary)
                }
            }
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    @ViewBuilder
    private var previewImage: some View {
        if let localURL = viewModel.selectedLocalImageURL,
           let nsImage = NSImage(contentsOf: localURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let meta = viewModel.selectedMetadata,
                  let previewURL = meta.imageURLs(preferUHD: false).first {
            AsyncImage(url: previewURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                case .empty:
                    ZStack {
                        placeholderView
                        ProgressView()
                            .controlSize(.small)
                    }
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.35), Color.indigo.opacity(0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private func dayBadgeTitle(for index: Int, metadata: BingImageMetadata?) -> String {
        if index == 0 {
            return "Today"
        } else if index == 1 {
            return "Yesterday"
        } else if let date = metadata?.formattedDate {
            return date
        }
        return "\(index)d ago"
    }

    private func shortDayLabel(for index: Int, metadata: BingImageMetadata) -> String {
        if index == 0 { return "Today" }
        if index == 1 { return "Yest." }
        if let date = metadata.parsedDate {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(index)d"
    }

    // MARK: - Metadata & Actions

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.selectedMetadata?.displayTitle ?? "Bing Daily Wallpaper")
                .font(.headline)
                .lineLimit(2)

            if let attribution = viewModel.selectedMetadata?.attribution, !attribution.isEmpty {
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let infoURL = viewModel.selectedMetadata?.infoURL {
                Link(destination: infoURL) {
                    Label("Story on Bing", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if viewModel.selectedIndex == 0 {
                        await viewModel.updateToToday(force: true, trigger: "Manual")
                    } else {
                        await viewModel.applySelectedMetadata()
                    }
                }
            } label: {
                Label(
                    viewModel.selectedIndex == 0
                        ? (viewModel.isSelectedCurrentlyApplied ? "Refresh Today's Wallpaper" : "Apply Today's Wallpaper")
                        : "Switch to This Day's Wallpaper",
                    systemImage: viewModel.selectedIndex == 0 ? "arrow.clockwise" : "display.2"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.isUpdating)

            if viewModel.selectedMetadata != nil {
                Button {
                    if let meta = viewModel.selectedMetadata {
                        Task { await viewModel.saveCopyOfMetadata(meta) }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("Save a copy of this wallpaper…")
                .disabled(viewModel.isUpdating)
            }
        }
    }

    // MARK: - Missing Permissions Alert (shown only when permissions are missing)

    @ViewBuilder
    private var permissionAlertBanner: some View {
        let missingPermissions = viewModel.systemCheckReport.items.filter { $0.severity == .actionRequired }
        if !missingPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(missingPermissions) { item in
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 6)

                        if let action = item.fixAction, let label = item.fixLabel {
                            Button(label) {
                                viewModel.performCheckFix(action)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.75)
            )
        }
    }
}
