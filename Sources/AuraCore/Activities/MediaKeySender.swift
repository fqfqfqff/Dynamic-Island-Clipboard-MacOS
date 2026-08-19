import AppKit

/// Системные медиа-клавиши: ими управляется тот источник, который сейчас играет,
/// включая браузеры и мессенджеры, до которых AppleScript не дотягивается.
enum MediaKeySender {
    private static let playPause: Int32 = 16
    private static let next: Int32 = 17
    private static let previous: Int32 = 18

    static func send(_ command: NowPlayingProvider.Command) {
        let key = switch command {
        case .togglePlayPause: playPause
        case .next: next
        case .previous: previous
        }
        post(key: key, down: true)
        post(key: key, down: false)
    }

    private static func post(key: Int32, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
        let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
