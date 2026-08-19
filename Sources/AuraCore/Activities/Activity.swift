import AppKit
import SwiftUI

/// Всё, что вырез показывает, — это активность: музыка, зарядка, таймер,
/// уведомление, прогресс чужой задачи. Один тип на всех, поэтому новый источник
/// добавляется провайдером и не требует правок в UI.
struct Activity: Identifiable, Equatable {
    enum Priority: Int, Comparable {
        /// Фоновое, показываем если места хватает.
        case ambient
        case normal
        /// Вытесняет обычные (таймер на исходе, уведомление).
        case important
        /// Не вытесняется ничем (батарея на нуле).
        case critical

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Что показывать в правом компактном слоте.
    enum Indicator: Equatable {
        case none
        case progress(Double)
        case text(String)
        /// Работа идёт, но её длительность неизвестна.
        case pulse
        /// Анимированные полоски — играет звук.
        case audioBars
    }

    /// Стабильный идентификатор: повторный `upsert` с тем же id обновляет
    /// активность на месте, а не плодит дубли.
    let id: String
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    /// Если есть — в компактном слоте вместо иконки показывается она.
    var artwork: NSImage?
    /// Файл, к которому относится активность: его можно открыть и перетащить.
    var fileURL: URL?
    var priority: Priority = .normal
    var indicator: Indicator = .none
    var createdAt: Date = Date()
    /// nil — живёт, пока провайдер не уберёт сам.
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}
