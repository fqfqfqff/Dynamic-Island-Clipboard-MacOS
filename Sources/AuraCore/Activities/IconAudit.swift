import Foundation

/// Проверка поиска иконок приложений — снаружи, как отдельный режим
/// инструмента снимков.
///
/// Поломка здесь не видна на глаз: в диагностике одного уведомления «значок
/// найден» стоит и тогда, когда найдена нарисованная нами буква. А имена
/// приложений переводятся, и достаточно одной ошибки в разборе перевода,
/// чтобы иконок не стало сразу у половины системы.
public enum IconAudit {
    public struct Entry: Sendable {
        public let name: String
        public let found: Bool
        public let monogram: Bool
    }

    @MainActor
    public static func run() -> [Entry] {
        NotificationMirrorProvider.iconAudit().map {
            Entry(name: $0.name, found: $0.found, monogram: $0.monogram)
        }
    }
}
