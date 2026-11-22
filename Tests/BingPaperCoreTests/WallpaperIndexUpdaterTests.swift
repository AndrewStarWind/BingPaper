import BingPaperCore
import Foundation
import Testing

@Suite("WallpaperIndexUpdater")
struct WallpaperIndexUpdaterTests {
    @Test("Updates AllSpacesAndDisplays, SystemDefault, Displays, and Spaces with binary EncodedOptionValues while preserving Idle")
    func updatesAllScopesAndPreservesIdle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingPaperIndexTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexURL = tempDir.appendingPathComponent("Index.plist")
        let backupDir = tempDir.appendingPathComponent("Backups", isDirectory: true)
        let imageURL = tempDir.appendingPathComponent("bing-20261122-en-US-UHD.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: imageURL)

        let existingIdle: [String: Any] = [
            "Content": [
                "Choices": [
                    ["Provider": "com.apple.wallpaper.choice.aerials", "Files": []]
                ],
                "EncodedOptionValues": "$null"
            ]
        ]

        let initialScope: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [
                        ["Provider": "com.apple.wallpaper.choice.aerials", "Files": []]
                    ]
                ]
            ],
            "Idle": existingIdle,
            "Linked": [
                "Content": [
                    "Choices": [
                        ["Provider": "com.apple.wallpaper.choice.aerials", "Files": []]
                    ]
                ]
            ],
            "Type": "linked"
        ]

        let mockRoot: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Idle": existingIdle,
                "Type": "idle"
            ],
            "SystemDefault": initialScope,
            "Displays": [
                "DISPLAY-1": initialScope,
                "DISPLAY-2": initialScope
            ],
            "Spaces": [
                "SPACE-A": [
                    "Default": initialScope,
                    "Displays": [
                        "DISPLAY-1": initialScope,
                        "DISPLAY-2": initialScope
                    ]
                ]
            ]
        ]

        let initialData = try PropertyListSerialization.data(fromPropertyList: mockRoot, format: .binary, options: 0)
        try initialData.write(to: indexURL)

        let updater = WallpaperIndexUpdater()
        let result = try updater.applyWallpaper(
            imageURL: imageURL,
            scalingMode: .fillScreen,
            toIndexAt: indexURL,
            backupDirectory: backupDir
        )

        #expect(result.scopesUpdated == 7)
        #expect(result.reusedNativeChoice == false)
        #expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("Index.plist.initial.bak").path))

        let updatedData = try Data(contentsOf: indexURL)
        let updatedRoot = try #require(
            PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil) as? [String: Any]
        )

        func verifyScope(_ scope: [String: Any]) throws {
            #expect(scope["Type"] as? String == "individual")

            let desktop = try #require(scope["Desktop"] as? [String: Any])
            let content = try #require(desktop["Content"] as? [String: Any])
            let choices = try #require(content["Choices"] as? [[String: Any]])
            let choice = try #require(choices.first)

            #expect(choice["Provider"] as? String == WallpaperIndexUpdater.imageProviderID)
            let files = try #require(choice["Files"] as? [[String: Any]])
            #expect(files.isEmpty)

            // EncodedOptionValues MUST be a binary plist Data blob (never "$base64" string!)
            let encodedOptions = try #require(content["EncodedOptionValues"] as? Data)
            let decodedOptions = try #require(
                PropertyListSerialization.propertyList(from: encodedOptions, options: [], format: nil) as? [String: Any]
            )
            let values = try #require(decodedOptions["values"] as? [String: Any])
            #expect(values["placement"] != nil)

            let configBlob = try #require(choice["Configuration"] as? Data)
            let inner = try #require(
                PropertyListSerialization.propertyList(from: configBlob, options: [], format: nil) as? [String: Any]
            )
            #expect(inner["type"] as? String == "imageFile")
            let urlDict = try #require(inner["url"] as? [String: Any])
            #expect(urlDict["relative"] as? String == imageURL.standardizedFileURL.absoluteString)

            // Idle (Screen Saver) must remain preserved!
            let idle = try #require(scope["Idle"] as? [String: Any])
            let idleContent = try #require(idle["Content"] as? [String: Any])
            let idleChoices = try #require(idleContent["Choices"] as? [[String: Any]])
            #expect(idleChoices.first?["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
        }

        try verifyScope(try #require(updatedRoot["AllSpacesAndDisplays"] as? [String: Any]))
        try verifyScope(try #require(updatedRoot["SystemDefault"] as? [String: Any]))

        let displays = try #require(updatedRoot["Displays"] as? [String: Any])
        try verifyScope(try #require(displays["DISPLAY-1"] as? [String: Any]))
        try verifyScope(try #require(displays["DISPLAY-2"] as? [String: Any]))

        let spaces = try #require(updatedRoot["Spaces"] as? [String: Any])
        let spaceA = try #require(spaces["SPACE-A"] as? [String: Any])
        try verifyScope(try #require(spaceA["Default"] as? [String: Any]))
        let spaceDisplays = try #require(spaceA["Displays"] as? [String: Any])
        try verifyScope(try #require(spaceDisplays["DISPLAY-1"] as? [String: Any]))
        try verifyScope(try #require(spaceDisplays["DISPLAY-2"] as? [String: Any]))
    }

    @Test("Clones native Choice and binary EncodedOptionValues when NSWorkspace wrote Files=[] and URL inside Configuration")
    func clonesNativeChoiceFromConfigurationBlob() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BingPaperNativeClone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexURL = tempDir.appendingPathComponent("Index.plist")
        let imageURL = tempDir.appendingPathComponent("bing-native.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: imageURL)

        let nativeConfigBlob = try PropertyListSerialization.data(
            fromPropertyList: [
                "type": "imageFile",
                "url": ["relative": imageURL.standardizedFileURL.absoluteString]
            ],
            format: .binary,
            options: 0
        )
        let nativeOptionsBlob = try WallpaperIndexUpdater.makeDefaultEncodedOptionValues(scalingMode: .fillScreen)

        let nativeChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [[String: Any]](),
            "Configuration": nativeConfigBlob,
            "CustomOS27Key": "preserved"
        ]

        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "idle"
            ],
            "SystemDefault": [
                "Desktop": [
                    "Content": [
                        "Choices": [nativeChoice],
                        "EncodedOptionValues": nativeOptionsBlob
                    ]
                ],
                "Type": "individual"
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try data.write(to: indexURL)

        let result = try WallpaperIndexUpdater().applyWallpaper(imageURL: imageURL, toIndexAt: indexURL)
        #expect(result.reusedNativeChoice == true)

        let reloaded = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: indexURL), options: [], format: nil) as? [String: Any]
        )
        let allSpaces = try #require(reloaded["AllSpacesAndDisplays"] as? [String: Any])
        let desktop = try #require(allSpaces["Desktop"] as? [String: Any])
        let content = try #require(desktop["Content"] as? [String: Any])
        let choices = try #require(content["Choices"] as? [[String: Any]])
        #expect(choices.first?["CustomOS27Key"] as? String == "preserved")
        #expect(content["EncodedOptionValues"] as? Data == nativeOptionsBlob)
    }
}
