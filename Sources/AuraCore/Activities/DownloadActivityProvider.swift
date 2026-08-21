import AppKit
import SwiftUI

/// Показывает в вырезе идущие загрузки.
///
/// Сводного индикатора скачиваний в macOS нет: каждый браузер показывает
/// прогресс у себя, и чтобы узнать, докачался ли файл, нужно найти его окно.
/// А вырез виден всегда.
///
/// Общего API для этого тоже нет, зато есть общий след: все браузеры пишут
/// во временный файл рядом с будущим результатом и переименовывают его,
/// когда закончат. За папкой загрузок и следим.
///
/// Процентов здесь намеренно нет — полного размера файла из временного не
/// узнать, а рисовать выдуманную полосу хуже, чем не рисовать никакой.
/// Вместо процентов растёт число скачанных мегабайт.
@MainActor
final class DownloadActivityProvider {
    private let center: ActivityCenter
    private var watcher: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var ticker: Timer?
    /// Временный файл → его размер и когда он последний раз рос.
    private var active: [URL: (size: Int64, grewAt: Date)] = [:]

    /// Сколько файл может не расти, прежде чем считать загрузку брошенной.
    ///
    /// Недокачанные файлы остаются в папке навсегда: браузер закрыли, сеть
    /// пропала, загрузку отменили. Без этого срока такой файл висел бы
    /// в вырезе вечно — в папке загрузок владельца как раз лежал один
    /// с прошлого года.
    private static let staleAfter: TimeInterval = 90

    /// Хвосты, которыми браузеры помечают недокачанное.
    private static let temporaryExtensions: Set<String> = [
        "crdownload",   // Chrome, Edge, Arc
        "download",     // Safari
        "part",         // Firefox
        "partial",
        "opdownload",   // Opera
    ]

    private static let folder: URL? = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first

    init(center: ActivityCenter) {
        self.center = center
    }

    func start() {
        stop()
        guard let folder = Self.folder else { return }

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        watcher.resume()
        self.watcher = watcher

        scan()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        stopTicking()

        for url in active.keys { center.remove(id: Self.activityID(for: url)) }
        active.removeAll()
    }

    // MARK: - Наблюдение

    /// Пока что-то качается, размер обновляется раз в секунду. Файловая
    /// система сообщает о записи в папку, но не о росте файла внутри неё.
    private func startTicking() {
        guard ticker == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scan() {
        guard let folder = Self.folder else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let current = contents.filter {
            Self.temporaryExtensions.contains($0.pathExtension.lowercased())
        }

        // Исчезнувшие временные файлы — это либо докачанные, либо отменённые.
        for url in active.keys where !current.contains(url) {
            finish(url)
        }

        let now = Date()
        var live = 0

        for url in current {
            let size = Self.size(of: url)
            let grewAt: Date

            if let previous = active[url] {
                grewAt = previous.size == size ? previous.grewAt : now
            } else {
                // Первая встреча: время берём из самого файла, а не «сейчас».
                // Иначе недокачанный с прошлой недели считается свежим и
                // висит в вырезе полторы минуты после каждого запуска —
                // ровно это владелец и увидел.
                grewAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? now
            }
            active[url] = (size, grewAt)

            // Файл не растёт слишком долго — загрузка брошена. Из выреза
            // убираем, но из виду не теряем: он может ожить.
            guard now.timeIntervalSince(grewAt) < Self.staleAfter else {
                center.remove(id: Self.activityID(for: url))
                continue
            }
            live += 1

            center.upsert(
                Activity(
                    id: Self.activityID(for: url),
                    title: Self.finalName(for: url),
                    subtitle: Self.wording(size: size),
                    symbol: "arrow.down.circle.fill",
                    tint: .blue,
                    priority: .normal,
                    indicator: .pulse
                )
            )
        }

        live == 0 ? stopTicking() : startTicking()
    }

    /// Временного файла больше нет. Если рядом появился настоящий — значит,
    /// докачалось, и его стоит показать: по нему можно кликнуть и перетащить.
    private func finish(_ url: URL) {
        active[url] = nil
        center.remove(id: Self.activityID(for: url))

        let name = Self.finalName(for: url)
        let result = url.deletingLastPathComponent().appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: result.path) else { return }

        center.upsert(
            Activity(
                id: "download.done.\(name)",
                title: t("ui.1f8a2c05", "Загружено"),
                subtitle: name,
                symbol: "arrow.down.circle.fill",
                tint: .green,
                fileURL: result,
                priority: .normal,
                indicator: .none,
                expiresAt: Date().addingTimeInterval(8)
            )
        )
    }

    // MARK: - Разбор

    private static func activityID(for url: URL) -> String {
        "download.\(url.lastPathComponent)"
    }

    /// Имя, которое файл получит после загрузки: у Safari временный файл —
    /// это папка «Имя.download», у остальных — «Имя.расширение.crdownload».
    nonisolated static func finalName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    nonisolated static func wording(size: Int64) -> String {
        guard size > 0 else { return t("ui.2d90b4e7", "Начинается") }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            // У Safari недокачанное лежит внутри папки-пакета.
            let inner = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            return inner.reduce(0) { total, file in
                total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return Int64(values?.fileSize ?? 0)
    }
}
