import Foundation

/// Исполнитель AppleScript со своим кэшем.
///
/// `NSAppleScript` не предназначен для передачи между потоками, а компиляция
/// стоит заметного времени — поэтому и кэш, и само выполнение живут внутри
/// актора: наружу выходит только результат.
actor AppleScriptRunner {
    enum Outcome: Sendable {
        case success(String)
        /// Пользователь запретил управление приложением (−1743).
        case denied
        case failed(Int)
    }

    private var compiled: [String: NSAppleScript] = [:]

    func run(source: String, key: String) -> Outcome {
        let script: NSAppleScript
        if let cached = compiled[key] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return .failed(-1) }
            compiled[key] = created
            script = created
        }

        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            return code == -1743 ? .denied : .failed(code)
        }
        return .success(output.stringValue ?? "")
    }
}
