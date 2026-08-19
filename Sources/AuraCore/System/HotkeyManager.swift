import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon `RegisterEventHotKey`.
///
/// API древний, но живой и, в отличие от `NSEvent.addGlobalMonitorForEvents`
/// для клавиатуры, не требует разрешения Accessibility.
final class HotkeyManager {
    /// Единственный экземпляр живёт на главном потоке: Carbon-обработчики
    /// приходят в главный рун-луп, и делить их между потоками нечего.
    @MainActor
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32

        /// ⌥⌘V — историю буфера открывают поверх обычной вставки, поэтому
        /// сочетание намеренно близко к ⌘V.
        static let clipboardHistory = Shortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(optionKey | cmdKey)
        )

        /// ⌥⌘M — витрина плеера на весь экран.
        static let showcase = Shortcut(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(optionKey | cmdKey)
        )
    }

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        handlers[id] = handler

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x41555241), id: id)  // 'AURA'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            registered.append(ref)
        } else {
            NSLog("Aura: не удалось зарегистрировать хоткей, код %d", status)
            handlers[id] = nil
        }
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}

/// C-колбэк не может захватывать контекст, поэтому идёт через синглтон.
private let hotkeyEventCallback: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        HotkeyManager.shared.fire(id)
    }
    return noErr
}
