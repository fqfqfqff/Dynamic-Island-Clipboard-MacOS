import Foundation

/// Поиск кэша иконок, которые система показывает у уведомлений с телефона.
///
/// Иконки в базе Центра уведомлений нет — проверено. Значит, система держит
/// её где-то ещё: она приходит по Continuity вместе с уведомлением и должна
/// оседать в кэше.
enum IconHunt {
    static func look() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let places = [
            "Library/Group Containers/group.com.apple.usernoted",
            "Library/Containers/com.apple.notificationcenterui/Data/Library/Caches",
            "Library/Caches/com.apple.notificationcenterui",
            "Library/Application Support/com.apple.sharingd",
            "Library/Caches/com.apple.sharingd",
            "Library/Containers/com.apple.NotificationCenter",
        ]

        var lines: [String] = []
        for place in places {
            let url = home.appendingPathComponent(place)
            guard FileManager.default.fileExists(atPath: url.path) else {
                lines.append("нет: \(place)")
                continue
            }

            let items = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
            )) ?? []

            let described = items.prefix(12).map { item -> String in
                let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let folder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return folder ? "\(item.lastPathComponent)/" : "\(item.lastPathComponent) \(size)"
            }
            lines.append("\(place): " + described.joined(separator: ", "))
        }
        return lines
    }
}
