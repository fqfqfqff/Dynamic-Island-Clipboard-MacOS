import AppKit
import ScreenCaptureKit

/// Значок приложения, снятый с самого баннера.
///
/// Уведомления с айфона приходят от приложений, которых на Маке нет и быть
/// не может: Инстаграм, банк, доставка. Найти их иконку негде — а в баннере
/// она есть, система рисует её сама. Единственный способ её получить — снять
/// с экрана тот кусок баннера, где она нарисована.
///
/// Это требует разрешения на запись экрана. Спрашиваем его не при запуске,
/// а в первый раз, когда иконку действительно негде взять: у большинства
/// уведомлений приложение стоит на Маке, и разрешение им не нужно.
@MainActor
final class BannerIconReader {
    /// Снятые значки живут между запусками: приложения на телефоне
    /// не меняются, а снимать экран лишний раз незачем.
    private var cache: [String: NSImage] = [:]
    private var pending: Set<String> = []

    private var folder: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura/banner-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func fileURL(for app: String) -> URL {
        // Имя приложения в имени файла — не лучшая мысль: там бывает всё
        // что угодно, включая косые черты.
        let safe = app.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return folder.appendingPathComponent(String(safe) + ".png")
    }

    func cached(for app: String) -> NSImage? {
        if let image = cache[app] { return image }
        guard let image = NSImage(contentsOf: fileURL(for: app)) else { return nil }
        cache[app] = image
        return image
    }

    /// Снимает значок с баннера и отдаёт его, когда получится.
    ///
    /// `frame` — прямоугольник значка в координатах экрана, полученный
    /// через Универсальный доступ: он точнее любых угаданных отступов
    /// и не зависит от версии системы.
    /// Срезать ли уголок со значком телефона. Ставится снаружи, из настроек.
    var trimsBadge = true

    /// Разрешена ли запись экрана. Без неё снять значок неоткуда.
    var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Когда можно снова спрашивать разрешение. Отказ — это ответ: долбить
    /// системный диалог на каждое уведомление нельзя.
    private var askAgainAfter: Date?

    func read(app: String, iconFrame frame: CGRect, completion: @escaping (NSImage) -> Void) {
        guard cached(for: app) == nil, !pending.contains(app) else { return }
        guard frame.width > 8, frame.height > 8 else { return }

        guard isAllowed else {
            requestAccessIfDue()
            return
        }
        pending.insert(app)

        // Немного внутрь: в поле значка входит и воздух вокруг него.
        // Обрезать по краю самой иконки не выходит — на тёмном баннере
        // тёмная иконка от фона неотличима, и обрез съедал её саму.
        let tight = frame.insetBy(dx: frame.width * 0.06, dy: frame.height * 0.06)

        Task { [weak self] in
            let image = await Self.capture(frame: tight)
            await MainActor.run {
                guard let self else { return }
                self.pending.remove(app)
                guard let image else {
                    AppDelegate.log("значок с баннера: снимок не получился")
                    return
                }
                guard Self.looksLikeIcon(image) else {
                    AppDelegate.log("значок с баннера: в кадре пусто, отброшен")
                    return
                }

                let clean = self.trimsBadge ? Self.withoutPhoneBadge(image) : image
                let shaped = Self.rounded(clean)
                self.cache[app] = shaped
                if let data = shaped.pngData { try? data.write(to: self.fileURL(for: app)) }
                completion(shaped)
            }
        }
    }

    /// Просит разрешение — один раз за десять минут, не чаще.
    ///
    /// Первый вызов показывает системный диалог. Если человек уже отказал,
    /// диалога больше не будет: включать придётся руками в «Настройках
    /// системы», и об этом честно пишем в журнал.
    private func requestAccessIfDue() {
        if let askAgainAfter, askAgainAfter > Date() { return }
        askAgainAfter = Date().addingTimeInterval(600)

        let granted = CGRequestScreenCaptureAccess()
        AppDelegate.log(
            granted
                ? "значок с баннера: запись экрана разрешена"
                : "значок с баннера: нужна запись экрана — Настройки → Конфиденциальность → Запись экрана"
        )
    }

    /// Снимок области экрана в файл — для разбора.
    static func shot(of area: CGRect, completion: @escaping (URL?) -> Void) {
        Task {
            let image = await capture(frame: area)
            await MainActor.run {
                guard let data = image?.pngData else { return completion(nil) }
                let url = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Aura/banner-shot.png")
                try? data.write(to: url)
                completion(url)
            }
        }
    }

    // MARK: - Снимок экрана

    /// Снимает прямоугольник экрана через ScreenCaptureKit.
    ///
    /// Именно экрана, а не окна: окно баннера принадлежит системному процессу
    /// и в списке доступных для захвата окон его может не быть вовсе.
    private static func capture(frame: CGRect) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: {
                $0.frame.intersects(frame)
            }) ?? content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = frame
            // Втрое от точек: экран и так рисуется вдвое, но третий проход
            // избавляет от второго пересчёта при показе — значок рисуется
            // крупнее, чем снят, и мылится именно на этом шаге.
            configuration.width = Int(frame.width * 3)
            configuration.height = Int(frame.height * 3)
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let shot = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            )
            return NSImage(cgImage: shot, size: frame.size)
        } catch {
            await MainActor.run {
                AppDelegate.log("значок с баннера: съёмка не удалась — \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Скругляет снятый квадрат по форме иконки приложения.
    ///
    /// С экрана значок снимается прямоугольником вместе с фоном баннера,
    /// и в карточке он выглядел вырезанным из чужой картинки: тёмные углы
    /// выдают квадрат там, где у всех остальных приложений скруглённая
    /// форма. Радиус — как у иконок macOS, примерно четверть стороны.
    static func rounded(_ image: NSImage) -> NSImage {
        let side = min(image.size.width, image.size.height)
        guard side > 4 else { return image }

        let size = CGSize(width: side, height: side)
        let result = NSImage(size: size)

        result.lockFocus()
        let box = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: box, xRadius: side * 0.23, yRadius: side * 0.23)
        path.addClip()

        // Рисуем по центру: снятый кадр может быть чуть шире квадрата.
        let origin = NSPoint(
            x: (side - image.size.width) / 2,
            y: (side - image.size.height) / 2
        )
        image.draw(
            in: NSRect(origin: origin, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        result.unlockFocus()

        return result
    }

    /// Срезает уголок со значком телефона.
    ///
    /// Уведомление, прилетевшее с айфона, macOS помечает маленьким телефоном
    /// в правом нижнем углу иконки — своей пометкой «это не отсюда». В снимок
    /// он попадает вместе с иконкой, и в вырезе выглядит грязью: у остальных
    /// приложений значок чистый.
    ///
    /// Срезаем правый нижний угол и растягиваем остаток обратно в квадрат.
    /// Иконки редко несут что-то важное в самом углу, а телефон уходит
    /// целиком.
    static func withoutPhoneBadge(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let source = rep.cgImage else { return image }

        let side = min(rep.pixelsWide, rep.pixelsHigh)
        let keep = Int(Double(side) * 0.84)
        guard keep > 8 else { return image }

        // Верхний левый квадрат: в системе координат CGImage начало — сверху.
        guard let cropped = source.cropping(
            to: CGRect(x: 0, y: 0, width: keep, height: keep)
        ) else { return image }

        let size = CGSize(width: image.size.width, height: image.size.height)
        return NSImage(cgImage: cropped, size: size)
    }

    /// Отсев пустышек: если баннер уже уехал, в кадр попадёт стол или пустота.
    /// Иконка — это цветной непрозрачный квадрат, и по этому её видно.
    static func looksLikeIcon(_ image: NSImage) -> Bool {
        guard let data = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data),
              rep.pixelsWide > 4, rep.pixelsHigh > 4 else { return false }

        var different = 0
        var checked = 0
        var first: NSColor?

        for x in stride(from: 2, to: rep.pixelsWide - 2, by: 3) {
            for y in stride(from: 2, to: rep.pixelsHigh - 2, by: 3) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                checked += 1
                guard let first else { first = color; continue }
                if abs(color.brightnessComponent - first.brightnessComponent) > 0.08 {
                    different += 1
                }
            }
        }

        guard checked > 20 else { return false }
        // Однотонный квадрат — это не иконка, а кусок фона.
        return Double(different) / Double(checked) > 0.08
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
