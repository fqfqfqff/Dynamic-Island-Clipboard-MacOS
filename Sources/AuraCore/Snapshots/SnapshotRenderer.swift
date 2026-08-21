import AppKit
import SwiftUI

/// Снимки интерфейса без разрешения на запись экрана.
///
/// Виды рисуются offscreen: `NSHostingView` кладётся в невидимое окно и
/// снимается через `cacheDisplay(in:to:)`. Это настоящий проход AppKit по
/// слоям, а не пересборка картинки — значит, в PNG попадает то же, что видит
/// пользователь, вместе с тенями и обводками.
///
/// `ImageRenderer` для этого не годится: он не умеет `NSVisualEffectView` и
/// backdrop-фильтры и отдаёт на их месте пустоту.
@MainActor
public enum SnapshotRenderer {

    /// Рисует все сцены в каталог и возвращает пути записанных файлов.
    @discardableResult
    public static func renderAll(into directory: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        for scene in SnapshotScenes.all() {
            let url = directory.appendingPathComponent("\(scene.name).png")
            guard let data = png(of: scene) else {
                NSLog("Aura: сцена «\(scene.name)» не отрисовалась")
                continue
            }
            try? data.write(to: url)
            written.append(url)
        }
        return written
    }

    /// Один снимок сцены.
    public static func png(of scene: SnapshotScene) -> Data? {
        let hosting = NSHostingView(rootView: scene.content)
        hosting.frame = CGRect(origin: .zero, size: scene.size)

        // Виду нужно окно: вне окна слой не готовится к отрисовке и картинка
        // выходит пустой. Окно остаётся невидимым, но живёт на главном экране —
        // от него берётся масштаб, иначе снимок вышел бы в один пиксель на точку.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: scene.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.minX, y: screen.frame.minY))
        }

        // SwiftUI раскладывает содержимое не мгновенно: без прокрутки рун-лупа
        // в снимок попадает пустой кадр, а анимации не успевают встать в покой.
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(scene.settleTime))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        window.contentView = nil
        return rep.representation(using: .png, properties: [:])
    }
}

/// Одна сцена: имя файла, размер холста и само содержимое.
@MainActor
public struct SnapshotScene {
    public let name: String
    public let size: CGSize
    public let content: AnyView
    /// Сколько дать SwiftUI на раскладку и успокоение анимаций.
    public var settleTime: TimeInterval = 0.45

    public init(name: String, size: CGSize, settleTime: TimeInterval = 0.45, content: AnyView) {
        self.name = name
        self.size = size
        self.settleTime = settleTime
        self.content = content
    }
}
