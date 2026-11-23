import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Displays a temporary, non-interactive GPU-backed window directly above the desktop wallpaper layer
/// (and below Desktop icons, widgets, Dock, and app windows) while `WallpaperAgent` restarts,
/// eliminating the brief gray/black WindowServer flash.
@MainActor
final class SeamlessBackdropController {
    private var windows: [NSWindow] = []

    /// Shows backdrop windows covering every connected screen.
    /// - Parameters:
    ///   - imageProvider: Returns the image URL to display for a given screen.
    ///   - scalingMode: Scaling mode matching `NSWorkspace` / `WallpaperImageExtension`.
    func show(
        imageForScreen imageProvider: (NSScreen) -> URL?,
        scalingMode: WallpaperScalingMode
    ) {
        // Do not create UI windows in headless CLI mode (.prohibited).
        guard NSApp.activationPolicy() != .prohibited else { return }

        tearDownImmediately()

        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
        let gravity = Self.contentsGravity(for: scalingMode)
        var imageCache: [URL: CGImage] = [:]

        for screen in NSScreen.screens {
            guard let url = imageProvider(screen) else { continue }
            let cgImage: CGImage?
            if let cached = imageCache[url] {
                cgImage = cached
            } else {
                let loaded = Self.loadCGImage(from: url)
                if let loaded {
                    imageCache[url] = loaded
                }
                cgImage = loaded
            }
            guard let cgImage else { continue }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.backgroundColor = .black

            let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            contentView.wantsLayer = true
            if let layer = contentView.layer {
                layer.backgroundColor = NSColor.black.cgColor
                layer.contents = cgImage
                layer.contentsGravity = gravity
                layer.contentsScale = screen.backingScaleFactor
                layer.masksToBounds = true
            }
            window.contentView = contentView
            window.alphaValue = 1.0
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    /// Smoothly fades out and removes all backdrop windows once `WallpaperAgent` has finished rendering.
    func fadeOutAndClose(duration: TimeInterval = 0.25) async {
        guard !windows.isEmpty else { return }
        let activeWindows = windows

        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for window in activeWindows {
                    window.animator().alphaValue = 0.0
                }
            }, completionHandler: {
                Task { @MainActor in
                    for window in activeWindows {
                        window.orderOut(nil)
                        window.close()
                    }
                    continuation.resume()
                }
            })
        }

        windows.removeAll()
    }

    func tearDownImmediately() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private static func contentsGravity(for scalingMode: WallpaperScalingMode) -> CALayerContentsGravity {
        switch scalingMode {
        case .fillScreen: .resizeAspectFill
        case .fitToScreen: .resizeAspect
        case .stretchToFill: .resize
        case .center: .center
        }
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
