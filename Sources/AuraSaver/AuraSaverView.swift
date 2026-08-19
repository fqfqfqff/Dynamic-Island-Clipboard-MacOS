import AppKit
import ScreenSaver

/// Заставка Aura: показывает часы и то, что играет.
///
/// Это единственный законный способ вывести плеер поверх заблокированного
/// экрана: обычные окна там не рисуются вообще, а заставку запускает сама
/// система — в том числе на экране блокировки.
///
/// Плагин живёт в отдельном процессе и в песочнице, поэтому данные читает не
/// у приложения, а из файла в /Users/Shared, который Aura обновляет.
@objc(AuraSaverView)
public final class AuraSaverView: ScreenSaverView {
    private var snapshot: Snapshot?
    private var artwork: NSImage?
    private var artworkStamp: Date?
    private var lastRead = Date.distantPast

    // MARK: Данные

    /// Уменьшенная копия модели из приложения: плагин не линкуется с ним,
    /// чтобы не тащить в процесс заставки лишнего.
    private struct Snapshot: Codable {
        var title: String
        var subtitle: String?
        var appName: String
        var isPlaying: Bool
        var duration: TimeInterval?
        var elapsed: TimeInterval?
        var elapsedAt: Date
        var accentHex: String
        var artworkPath: String?
        var lyricPrevious: String?
        var lyric: String?
        var lyricNext: String?
        var updatedAt: Date

        var isFresh: Bool { Date().timeIntervalSince(updatedAt) < 30 }

        func progressNow() -> Double? {
            guard let duration, duration > 0, let elapsed else { return nil }
            let drift = isPlaying ? Date().timeIntervalSince(elapsedAt) : 0
            return min(1, max(0, (elapsed + drift) / duration))
        }

        func elapsedNow() -> TimeInterval? {
            guard let elapsed else { return nil }
            let drift = isPlaying ? Date().timeIntervalSince(elapsedAt) : 0
            return min(duration ?? .greatestFiniteMagnitude, elapsed + drift)
        }
    }

    private static let snapshotURL = URL(fileURLWithPath: "/Users/Shared/Aura/nowplaying.json")

    // MARK: Жизненный цикл

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 4
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 4
        wantsLayer = true
    }

    public override func animateOneFrame() {
        // Файл читаем раз в секунду, а перерисовываемся чаще — ради часов
        // и плавной полосы.
        if Date().timeIntervalSince(lastRead) > 1 {
            lastRead = Date()
            reload()
        }
        setNeedsDisplay(bounds)
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Self.snapshotURL) else {
            snapshot = nil
            artwork = nil
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try? decoder.decode(Snapshot.self, from: data)

        guard let path = snapshot?.artworkPath else {
            artwork = nil
            return
        }
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        if stamp != artworkStamp {
            artworkStamp = stamp
            artwork = NSImage(contentsOfFile: path)
        }
    }

    // MARK: Рисование

    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        drawBackdrop()

        // Часы не рисуем: на заблокированном экране их показывает сама
        // система, и вторые выглядели как ошибка. Заставка отвечает только
        // за то, чего в системе нет, — за плеер.
        if let snapshot, snapshot.isFresh {
            drawPlayer(snapshot)
        }
    }

    /// Фон — сильно увеличенная и затемнённая обложка.
    private func drawBackdrop() {
        guard let artwork else { return }

        let side = max(bounds.width, bounds.height) * 1.4
        let origin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
        artwork.draw(
            in: CGRect(origin: origin, size: CGSize(width: side, height: side)),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.28
        )

        NSColor.black.withAlphaComponent(0.55).setFill()
        bounds.fill()
    }

    private func drawPlayer(_ snapshot: Snapshot) {
        let side = scaled(260)
        let cardWidth = side + scaled(420)
        let left = bounds.midX - cardWidth / 2
        let bottom = bounds.midY - side / 2

        // Обложка
        let artworkRect = CGRect(x: left, y: bottom, width: side, height: side)
        let path = NSBezierPath(roundedRect: artworkRect, xRadius: scaled(20), yRadius: scaled(20))
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let artwork {
            artwork.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor.white.withAlphaComponent(0.08).setFill()
            artworkRect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Название и исполнитель — под обложкой, текст песни уходит вправо.
        let textLeft = artworkRect.maxX + scaled(56)
        let textWidth = cardWidth - side - scaled(56)

        let title = snapshot.title as NSString
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: scaled(34), weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let titleSize = title.boundingRect(
            with: CGSize(width: side, height: scaled(80)),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttributes
        )
        title.draw(
            with: CGRect(
                x: left,
                y: artworkRect.minY - titleSize.height - scaled(14),
                width: side,
                height: titleSize.height
            ),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttributes
        )

        let subtitle = snapshot.subtitle ?? snapshot.appName
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: scaled(17), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]
        (subtitle as NSString).draw(
            at: NSPoint(x: left, y: artworkRect.minY - titleSize.height - scaled(40)),
            withAttributes: subtitleAttributes
        )

        drawProgress(snapshot, left: left, width: side, bottom: artworkRect.minY - scaled(46))
        drawLyrics(snapshot, left: textLeft, width: textWidth, centerY: bounds.midY)
    }

    /// Текст песни колонкой справа: прошедшая строка приглушена,
    /// текущая выделена, следующая едва намечена.
    private func drawLyrics(_ snapshot: Snapshot, left: CGFloat, width: CGFloat, centerY: CGFloat) {
        let rows: [(String?, CGFloat, CGFloat, NSFont.Weight)] = [
            (snapshot.lyricNext, scaled(20), 0.28, .medium),
            (snapshot.lyric, scaled(29), 0.95, .semibold),
            (snapshot.lyricPrevious, scaled(20), 0.28, .medium),
        ]

        // Рисуем снизу вверх: в координатах AppKit ось Y растёт кверху,
        // а строки должны идти прошедшая → текущая → следующая.
        var y = centerY - scaled(60)
        for (text, size, alpha, weight) in rows {
            defer { y += size + scaled(26) }
            guard let text, !text.isEmpty else { continue }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            ]
            (text as NSString).draw(
                with: CGRect(x: left, y: y, width: width, height: size * 2.4),
                options: [.usesLineFragmentOrigin],
                attributes: attributes
            )
        }
    }

    private func drawProgress(_ snapshot: Snapshot, left: CGFloat, width: CGFloat, bottom: CGFloat) {
        guard let progress = snapshot.progressNow() else { return }

        let height = scaled(6)
        let track = CGRect(x: left, y: bottom, width: width, height: height)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()

        let filled = CGRect(x: left, y: bottom, width: width * progress, height: height)
        accentColor(snapshot.accentHex).setFill()
        NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: scaled(12), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
        ]
        (Self.time(snapshot.elapsedNow()) as NSString).draw(
            at: NSPoint(x: left, y: bottom - scaled(22)), withAttributes: attributes
        )

        let total = Self.time(snapshot.duration) as NSString
        let totalSize = total.size(withAttributes: attributes)
        total.draw(
            at: NSPoint(x: left + width - totalSize.width, y: bottom - scaled(22)),
            withAttributes: attributes
        )
    }

    // MARK: Мелочи

    /// В окне предпросмотра настроек всё то же самое, только мельче.
    private func scaled(_ value: CGFloat) -> CGFloat {
        isPreview ? value * 0.32 : value
    }

    private func accentColor(_ hex: String) -> NSColor {
        var value = hex
        guard value.hasPrefix("#") else { return .systemPink }
        value.removeFirst()
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return .systemPink }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func time(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
