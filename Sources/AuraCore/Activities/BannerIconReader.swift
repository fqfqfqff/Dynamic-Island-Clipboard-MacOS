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

                self.cache[app] = image
                if let data = image.pngData { try? data.write(to: self.fileURL(for: app)) }
                completion(image)
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
