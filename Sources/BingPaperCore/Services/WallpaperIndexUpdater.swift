import Foundation

public struct WallpaperIndexUpdateResult: Sendable, Equatable {
    public let indexPath: String
    public let scopesUpdated: Int
    public let reusedNativeChoice: Bool

    public init(indexPath: String, scopesUpdated: Int, reusedNativeChoice: Bool) {
        self.indexPath = indexPath
        self.scopesUpdated = scopesUpdated
        self.reusedNativeChoice = reusedNativeChoice
    }
}

public enum WallpaperIndexError: LocalizedError, Sendable, Equatable {
    case indexFileNotFound(String)
    case invalidPlistFormat(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .indexFileNotFound(let path):
            "macOS wallpaper store was not found at \(path)."
        case .invalidPlistFormat(let detail):
            "Could not parse macOS wallpaper store Index.plist: \(detail)"
        case .writeFailed(let detail):
            "Could not write updated macOS wallpaper store Index.plist: \(detail)"
        }
    }
}

/// Reads and updates macOS 14+ (Sonoma / Sequoia / Tahoe / macOS 27) `com.apple.wallpaper/Store/Index.plist`
/// so that the wallpaper is synchronized across every display, every Space (active and inactive), and the Lock Screen.
public struct WallpaperIndexUpdater: Sendable {
    public static let imageProviderID = "com.apple.wallpaper.choice.image"

    public static var defaultIndexURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist", isDirectory: false)
    }

    public init() {}

    /// Builds a valid macOS WallpaperAgent choice dictionary for a static image file URL.
    /// Matches macOS Sonoma–macOS 27's native schema (`Files = []`, URL stored in binary plist `Configuration`).
    public static func makeImageChoice(for imageURL: URL) throws -> [String: Any] {
        let relativeURI = imageURL.standardizedFileURL.absoluteString
        let innerConfiguration: [String: Any] = [
            "type": "imageFile",
            "url": [
                "relative": relativeURI
            ]
        ]
        let configBlob = try PropertyListSerialization.data(
            fromPropertyList: innerConfiguration,
            format: .binary,
            options: 0
        )
        return [
            "Configuration": configBlob,
            "Files": [[String: Any]](),
            "Provider": imageProviderID
        ]
    }

    /// Builds a valid macOS binary plist `EncodedOptionValues` blob for `com.apple.wallpaper.choice.image`
    /// when no existing native `EncodedOptionValues` Data blob can be cloned from `Index.plist`.
    public static func makeDefaultEncodedOptionValues(scalingMode: WallpaperScalingMode = .fillScreen) throws -> Data {
        let placementID: String = switch scalingMode {
        case .fillScreen: "Crop"
        case .fitToScreen: "SizeToFit"
        case .stretchToFill: "Stretch"
        case .center: "Centered"
        }

        let colorSpaceData = try PropertyListSerialization.data(
            fromPropertyList: "kCGColorSpaceGenericRGB",
            format: .binary,
            options: 0
        )

        let payload: [String: Any] = [
            "values": [
                "color": [
                    "color": [
                        "_0": [
                            "color": [
                                "components": [0.0, 0.0, 0.0, 1.0],
                                "colorSpace": colorSpaceData
                            ]
                        ]
                    ]
                ],
                "placement": [
                    "picker": [
                        "_0": [
                            "id": placementID
                        ]
                    ]
                ]
            ]
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .binary,
            options: 0
        )
    }

    /// Updates `Index.plist` across `AllSpacesAndDisplays`, `SystemDefault`, `Displays`, and `Spaces`
    /// so every monitor, Space, and the Lock Screen display `imageURL`.
    @discardableResult
    public func applyWallpaper(
        imageURL: URL,
        scalingMode: WallpaperScalingMode = .fillScreen,
        toIndexAt indexURL: URL = WallpaperIndexUpdater.defaultIndexURL,
        backupDirectory: URL? = nil,
        now: Date = Date()
    ) throws -> WallpaperIndexUpdateResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: indexURL.path) else {
            throw WallpaperIndexError.indexFileNotFound(indexURL.path)
        }

        let rawData = try Data(contentsOf: indexURL)

        // Create a one-time initial backup of the user's original Index.plist before modifying it.
        if let backupDirectory {
            let initialBackup = backupDirectory.appendingPathComponent("Index.plist.initial.bak")
            if !fm.fileExists(atPath: initialBackup.path) {
                try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try? rawData.write(to: initialBackup, options: .atomic)
            }
        }

        let parsed: Any
        do {
            parsed = try PropertyListSerialization.propertyList(from: rawData, options: [], format: nil)
        } catch {
            throw WallpaperIndexError.invalidPlistFormat(error.localizedDescription)
        }

        guard var root = parsed as? [String: Any] else {
            throw WallpaperIndexError.invalidPlistFormat("Root object is not a dictionary.")
        }

        let standardizedURI = imageURL.standardizedFileURL.absoluteString

        // Prefer cloning the exact native Choice & EncodedOptionValues (Data) written by NSWorkspace/WallpaperAgent
        // on this macOS version, falling back to any existing valid image EncodedOptionValues Data in Index.plist,
        // and finally to a properly encoded binary plist Data blob.
        let extractedNative = Self.findNativeChoice(matchingFileURI: standardizedURI, in: root)
        var choice = try extractedNative?.choice ?? Self.makeImageChoice(for: imageURL)
        // macOS 15–27 WallpaperImageExtension throws NSCocoaErrorDomain 4865 if Files contains legacy relative entries;
        // static image choices must use Files = [] and store the URL inside Configuration.
        choice["Files"] = [[String: Any]]()
        let encodedOptionValues: Data
        if let nativeOptions = extractedNative?.encodedOptionValues {
            encodedOptionValues = nativeOptions
        } else if let existingImageOptions = Self.findAnyImageEncodedOptionValues(in: root) {
            encodedOptionValues = existingImageOptions
        } else {
            encodedOptionValues = try Self.makeDefaultEncodedOptionValues(scalingMode: scalingMode)
        }

        var scopesUpdated = 0

        if var allSpaces = root["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces = Self.updateScopeDictionary(
                allSpaces,
                choice: choice,
                encodedOptionValues: encodedOptionValues,
                now: now
            )
            root["AllSpacesAndDisplays"] = allSpaces
            scopesUpdated += 1
        } else {
            root["AllSpacesAndDisplays"] = Self.makeFreshScopeDictionary(
                choice: choice,
                encodedOptionValues: encodedOptionValues,
                now: now
            )
            scopesUpdated += 1
        }

        if var systemDefault = root["SystemDefault"] as? [String: Any] {
            systemDefault = Self.updateScopeDictionary(
                systemDefault,
                choice: choice,
                encodedOptionValues: encodedOptionValues,
                now: now
            )
            root["SystemDefault"] = systemDefault
            scopesUpdated += 1
        }

        if var displays = root["Displays"] as? [String: Any] {
            for (displayKey, value) in displays {
                if var displayScope = value as? [String: Any] {
                    displayScope = Self.updateScopeDictionary(
                        displayScope,
                        choice: choice,
                        encodedOptionValues: encodedOptionValues,
                        now: now
                    )
                    displays[displayKey] = displayScope
                    scopesUpdated += 1
                }
            }
            root["Displays"] = displays
        }

        if var spaces = root["Spaces"] as? [String: Any] {
            for (spaceKey, value) in spaces {
                guard var spaceEntry = value as? [String: Any] else { continue }
                var modifiedSpace = false

                if var defaultScope = spaceEntry["Default"] as? [String: Any] {
                    defaultScope = Self.updateScopeDictionary(
                        defaultScope,
                        choice: choice,
                        encodedOptionValues: encodedOptionValues,
                        now: now
                    )
                    spaceEntry["Default"] = defaultScope
                    scopesUpdated += 1
                    modifiedSpace = true
                }

                if var spaceDisplays = spaceEntry["Displays"] as? [String: Any] {
                    for (displayKey, displayValue) in spaceDisplays {
                        if var displayScope = displayValue as? [String: Any] {
                            displayScope = Self.updateScopeDictionary(
                                displayScope,
                                choice: choice,
                                encodedOptionValues: encodedOptionValues,
                                now: now
                            )
                            spaceDisplays[displayKey] = displayScope
                            scopesUpdated += 1
                            modifiedSpace = true
                        }
                    }
                    spaceEntry["Displays"] = spaceDisplays
                }

                if modifiedSpace {
                    spaces[spaceKey] = spaceEntry
                }
            }
            root["Spaces"] = spaces
        }

        do {
            let outputData = try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .binary,
                options: 0
            )
            try outputData.write(to: indexURL, options: .atomic)
        } catch {
            throw WallpaperIndexError.writeFailed(error.localizedDescription)
        }

        return WallpaperIndexUpdateResult(
            indexPath: indexURL.path,
            scopesUpdated: scopesUpdated,
            reusedNativeChoice: extractedNative != nil
        )
    }

    // MARK: - Scope Helpers

    private struct ExtractedNativeChoice {
        let choice: [String: Any]
        let encodedOptionValues: Data?
    }

    /// Searches `Index.plist` for a native `Desktop` choice matching `uri` in either `Configuration` (binary plist)
    /// or `Files`, preferring entries that also carry a valid binary plist `EncodedOptionValues` Data blob.
    private static func findNativeChoice(matchingFileURI uri: String, in node: Any) -> ExtractedNativeChoice? {
        var fallbackMatch: ExtractedNativeChoice?
        findNativeChoiceRecursive(matchingFileURI: uri, in: node, fallback: &fallbackMatch)
        return fallbackMatch
    }

    private static func findNativeChoiceRecursive(
        matchingFileURI uri: String,
        in node: Any,
        fallback: inout ExtractedNativeChoice?
    ) {
        guard let dict = node as? [String: Any] else { return }

        if let desktop = dict["Desktop"] as? [String: Any],
           let content = desktop["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]] {
            for choice in choices where choiceMatchesURI(choice, targetURI: uri) {
                let optionsData = content["EncodedOptionValues"] as? Data
                let candidate = ExtractedNativeChoice(choice: choice, encodedOptionValues: optionsData)
                if let optionsData, !optionsData.isEmpty {
                    fallback = candidate
                    return
                } else if fallback == nil {
                    fallback = candidate
                }
            }
        }

        for (_, value) in dict {
            findNativeChoiceRecursive(matchingFileURI: uri, in: value, fallback: &fallback)
            if let existing = fallback?.encodedOptionValues, !existing.isEmpty {
                return
            }
        }
    }

    /// Finds any existing valid `EncodedOptionValues` Data blob belonging to a `com.apple.wallpaper.choice.image` entry.
    private static func findAnyImageEncodedOptionValues(in node: Any) -> Data? {
        guard let dict = node as? [String: Any] else { return nil }

        if let desktop = dict["Desktop"] as? [String: Any],
           let content = desktop["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           choices.contains(where: { ($0["Provider"] as? String) == imageProviderID }),
           let optionsData = content["EncodedOptionValues"] as? Data,
           !optionsData.isEmpty {
            return optionsData
        }

        for (_, value) in dict {
            if let found = findAnyImageEncodedOptionValues(in: value) {
                return found
            }
        }
        return nil
    }

    private static func choiceMatchesURI(_ choice: [String: Any], targetURI: String) -> Bool {
        let normalizedTarget = normalizeFileURI(targetURI)

        // 1. Check binary plist Configuration -> url -> relative (primary format on macOS 15–27)
        if let configData = choice["Configuration"] as? Data,
           let configDict = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any],
           let urlDict = configDict["url"] as? [String: Any],
           let relative = urlDict["relative"] as? String,
           normalizeFileURI(relative) == normalizedTarget {
            return true
        }

        // 2. Check Files -> relative (older Sonoma format)
        if let files = choice["Files"] as? [[String: Any]] {
            return files.contains { entry in
                guard let relative = entry["relative"] as? String else { return false }
                return normalizeFileURI(relative) == normalizedTarget
            }
        }

        return false
    }

    private static func normalizeFileURI(_ uri: String) -> String {
        if let url = URL(string: uri), url.isFileURL {
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return uri
    }

    private static func makeFreshScopeDictionary(
        choice: [String: Any],
        encodedOptionValues: Data,
        now: Date
    ) -> [String: Any] {
        let entry = makeWallpaperSlot(existing: nil, choice: choice, encodedOptionValues: encodedOptionValues, now: now)
        return [
            "Desktop": entry,
            "Type": "individual"
        ]
    }

    private static func updateScopeDictionary(
        _ scope: [String: Any],
        choice: [String: Any],
        encodedOptionValues: Data,
        now: Date
    ) -> [String: Any] {
        var updated = scope

        // Always update Desktop (controls active desktop + Lock Screen for static wallpapers).
        let existingDesktop = updated["Desktop"] as? [String: Any]
        updated["Desktop"] = makeWallpaperSlot(
            existing: existingDesktop,
            choice: choice,
            encodedOptionValues: encodedOptionValues,
            now: now
        )

        // Update Linked only if already present, and switch Type to "individual" so Desktop is authoritative
        // while preserving the user's Idle (Screen Saver) configuration untouched.
        if let existingLinked = updated["Linked"] as? [String: Any] {
            updated["Linked"] = makeWallpaperSlot(
                existing: existingLinked,
                choice: choice,
                encodedOptionValues: encodedOptionValues,
                now: now
            )
        }
        updated["Type"] = "individual"
        return updated
    }

    private static func makeWallpaperSlot(
        existing: [String: Any]?,
        choice: [String: Any],
        encodedOptionValues: Data,
        now: Date
    ) -> [String: Any] {
        var slot = existing ?? [:]
        var content = (slot["Content"] as? [String: Any]) ?? [:]
        content["Choices"] = [choice]
        content["EncodedOptionValues"] = encodedOptionValues
        if content["Shuffle"] == nil {
            content["Shuffle"] = "$null"
        }
        slot["Content"] = content
        slot["LastSet"] = now
        slot["LastUse"] = now
        return slot
    }
}
