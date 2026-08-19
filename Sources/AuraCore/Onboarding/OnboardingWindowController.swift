import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let media: NowPlayingProvider
    private let spectrum: AudioSpectrumMonitor

    init(settings: SettingsStore, media: NowPlayingProvider, spectrum: AudioSpectrumMonitor) {
        self.settings = settings
        self.media = media
        self.spectrum = spectrum
    }

    /// Показывает экран, если приложение запускается впервые.
    func showIfNeeded() {
        guard !settings.didCompleteOnboarding else { return }
        show()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: OnboardingView(onFinish: { [weak self] in self?.finish() })
                .environmentObject(settings)
                .environmentObject(media)
                .environmentObject(spectrum)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func finish() {
        settings.didCompleteOnboarding = true
        window?.close()
    }
}
