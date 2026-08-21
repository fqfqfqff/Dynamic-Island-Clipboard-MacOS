import AppKit

/// Что можно сделать с файлом, брошенным на вырез.
///
/// Полка — не единственное разумное действие: чаще файл бросают, чтобы
/// тут же его кому-то отправить или сжать. Меню под курсором превращает
/// вырез из «кармана» в место, куда можно бросить что угодно и выбрать.
@MainActor
final class DropActions: NSObject {
    private var urls: [URL] = []
    private let onShelf: ([URL]) -> Void

    init(onShelf: @escaping ([URL]) -> Void) {
        self.onShelf = onShelf
    }

    func present(for urls: [URL], at point: NSPoint) {
        guard !urls.isEmpty else { return }
        self.urls = urls

        let menu = NSMenu()
        menu.addItem(item(t("ui.9e0b3f71", "Положить на полку"), #selector(putOnShelf)))
        menu.addItem(item(t("ui.4c8d20a5", "Отправить по AirDrop"), #selector(sendViaAirDrop)))
        menu.addItem(item(t("ui.71fa60c3", "Сжать в архив"), #selector(compress)))
        menu.addItem(.separator())
        menu.addItem(item(t("ui.6e4b09d8", "Ничего"), #selector(cancel)))

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    // MARK: - Действия

    @objc private func putOnShelf() {
        onShelf(urls)
    }

    @objc private func sendViaAirDrop() {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    /// Сжатие через `ditto`: это тот же архиватор, которым пользуется Finder,
    /// поэтому и результат получается ровно таким же — без папки `__MACOSX`
    /// и с сохранёнными правами.
    @objc private func compress() {
        let files = urls
        guard let first = files.first else { return }

        let folder = first.deletingLastPathComponent()
        let name = files.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : "Архив"
        let destination = Self.freeName(in: folder, base: name, extension: "zip")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
            + files.map(\.path) + [destination.path]

        task.terminationHandler = { finished in
            guard finished.terminationStatus == 0 else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
        try? task.run()
    }

    @objc private func cancel() {
        urls = []
    }

    /// Свободное имя рядом: перезаписывать чужой архив нельзя.
    private static func freeName(in folder: URL, base: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
