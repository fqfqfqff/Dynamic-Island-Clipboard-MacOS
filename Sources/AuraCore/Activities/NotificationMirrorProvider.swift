import AppKit
import ApplicationServices
import SwiftUI

/// Показывает в вырезе уведомления других приложений.
///
/// Единого API для чтения чужих уведомлений в macOS нет. База Центра
/// уведомлений закрыта TCC и требует полного доступа к диску, поэтому здесь
/// выбран второй путь: наблюдение за окнами баннеров через Accessibility —
/// то же разрешение, которое уже нужно для вставки из буфера.
///
/// Системный баннер при этом никуда не девается: мы его дублируем, а не
/// заменяем — спрятать чужое окно приложение не может.
@MainActor
final class NotificationMirrorProvider {
    private let center: ActivityCenter
    private var observer: AXObserver?
    private var element: AXUIElement?
    private var seen: Set<String> = []

    private let bannerHost = "com.apple.notificationcenterui"

    init(center: ActivityCenter) {
        self.center = center
    }

    var isAvailable: Bool { AXIsProcessTrusted() }

    func start() {
        stop()
        guard AXIsProcessTrusted() else {
            NSLog("Aura: зеркало уведомлений не запущено — нет доступа к Универсальному доступу")
            return
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bannerHost
        ).first else { return }

        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        self.element = element

        var observer: AXObserver?
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard AXObserverCreate(pid, { _, element, _, context in
            guard let context else { return }
            let provider = Unmanaged<NotificationMirrorProvider>
                .fromOpaque(context).takeUnretainedValue()
            // Колбэк приходит на главном потоке рун-лупа, где наблюдатель и создан.
            MainActor.assumeIsolated { provider.handleBanner(element) }
        }, &observer) == .success, let observer else { return }

        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = observer
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        element = nil
        seen.removeAll()
    }

    // MARK: - Разбор баннера

    private func handleBanner(_ window: AXUIElement) {
        // Баннер дорисовывается не мгновенно: сразу после создания окна
        // текстов внутри ещё нет.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let texts = Self.texts(in: window)
            guard let content = Self.content(from: texts) else { return }
            self.present(content)
        }
    }

    private func present(_ content: Content) {
        // Один и тот же баннер система иногда пересоздаёт.
        let key = "\(content.app)|\(content.title)|\(content.body ?? "")"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        if seen.count > 40 { seen.removeFirst() }

        center.upsert(
            Activity(
                id: "notification.\(key.hashValue)",
                title: content.title,
                subtitle: content.body ?? content.app,
                symbol: "bell.fill",
                tint: .indigo,
                artwork: Self.icon(forAppNamed: content.app),
                priority: .important,
                indicator: .none,
                expiresAt: Date().addingTimeInterval(8)
            )
        )
    }

    struct Content: Equatable {
        var app: String
        var title: String
        var body: String?
    }

    /// Первая строка баннера — приложение, вторая — заголовок, остальное текст.
    nonisolated static func content(from texts: [String]) -> Content? {
        let cleaned = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Закрыть" && $0 != "Close" }

        guard cleaned.count >= 2 else { return nil }

        return Content(
            app: cleaned[0],
            title: cleaned[1],
            body: cleaned.count > 2 ? cleaned[2...].joined(separator: " ") : nil
        )
    }

    /// Собирает все текстовые узлы окна баннера.
    private static func texts(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []

        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                result.append(text)
                break
            }
        }

        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            for child in list {
                result.append(contentsOf: texts(in: child, depth: depth + 1))
            }
        }

        return result
    }

    private static func icon(forAppNamed name: String) -> NSImage? {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }?
            .icon
    }
}
