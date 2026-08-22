import AppKit
import ImageIO
import SwiftUI

/// Ловит новые снимки экрана и показывает их в вырезе с превью — снимок можно
/// сразу перетащить оттуда в письмо или чат, не заходя в папку.
@MainActor
final class ScreenshotActivityProvider {
    private let center: ActivityCenter
    private let clipboard: ClipboardService
    private let settings: SettingsStore
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var known: Set<String> = []
    private var folder: URL

    private let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "mov"]

    /// `folder` задаётся только в тестах: следить за настоящим рабочим столом
    /// они не должны.
    init(
        center: ActivityCenter,
        clipboard: ClipboardService,
        settings: SettingsStore,
        folder: URL? = nil
    ) {
        self.center = center
        self.clipboard = clipboard
        self.settings = settings
        self.folder = folder ?? Self.screenshotFolder()
    }

    func start() {
        stop()
        known = Set(Self.files(in: folder, extensions: extensions).map(\.lastPathComponent))

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Aura: не удалось наблюдать за папкой снимков %@", folder.path)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        // Дескриптор захватывается значением, а не читается через `self`.
        // Отмена приходит асинхронно: к моменту, когда обработчик отработает,
        // `self.descriptor` уже может указывать на новое слежение — и тогда
        // старая отмена закроет свежий дескриптор. Именно так молча ломались
        // снимки экрана: второй `start()` следил за закрытым файлом, событий
        // не приходило, ошибок тоже.
        let watched = descriptor
        source.setCancelHandler { close(watched) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Почему снимки могут не появляться. Папку снимков закрывает TCC:
    /// приложение без разрешения на «Рабочий стол» видит её пустой — молча,
    /// без ошибки. Отличить это от «просто ничего не снимали» иначе нельзя.
    var diagnostics: [String: Any] {
        [
            "папка": folder.path,
            "слежение": source != nil,
            "видноФайлов": Self.files(in: folder, extensions: extensions).count,
            "вБуфер": settings.copyScreenshotToClipboard,
        ]
    }

    private func scan() {
        let files = Self.files(in: folder, extensions: extensions)
        let names = Set(files.map(\.lastPathComponent))
        defer { known = names }

        let added = names.subtracting(known)
        guard !added.isEmpty else { return }

        for url in files where added.contains(url.lastPathComponent) {
            // Снимок пишется не мгновенно — даём файлу дописаться.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.present(url)
            }
        }
    }

    private func present(_ url: URL) {
        let isScreenshot = url.lastPathComponent.lowercased().contains("screenshot")
            || url.lastPathComponent.hasPrefix("Снимок экрана")
            || url.lastPathComponent.hasPrefix("CleanShot")

        // Снимок сразу ложится в историю буфера — оттуда его можно вставить
        // куда угодно, не открывая папку.
        clipboard.add(
            ClipboardItem(
                kind: .files([url]),
                date: Date(),
                sourceName: isScreenshot ? "Снимок экрана" : "Новый файл"
            )
        )

        // В системный буфер — только снимки. На рабочий стол попадает и всё
        // скачанное, и подменять буфер каждый раз, когда там появился файл,
        // было бы прямым вредительством.
        if isScreenshot, settings.copyScreenshotToClipboard {
            clipboard.copyScreenshot(url)
        }

        center.upsert(
            Activity(
                id: "file.\(url.lastPathComponent)",
                title: isScreenshot ? "Снимок экрана" : url.lastPathComponent,
                subtitle: isScreenshot ? url.lastPathComponent : "Новый файл",
                symbol: "photo",
                tint: .teal,
                artwork: Self.thumbnail(for: url),
                fileURL: url,
                priority: .normal,
                indicator: .none,
                expiresAt: Date().addingTimeInterval(15)
            )
        )
    }

    /// Превью строится через ImageIO: он читает уменьшенную версию прямо из
    /// файла. Прежний вариант поднимал в память весь снимок целиком — под
    /// два десятка мегабайт ради картинки 96×96.
    private static func thumbnail(for url: URL) -> NSImage? {
        let side: CGFloat = 128
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(cgImage: image, size: CGSize(width: side, height: side))
    }

    private static func files(in folder: URL, extensions: Set<String>) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return (contents ?? []).filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    /// Пользователь мог сменить папку снимков в настройках системы.
    private static func screenshotFolder() -> URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let path = defaults?.string(forKey: "location") {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
