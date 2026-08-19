import AppKit
import AuraCore

@main
enum AuraMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // без иконки в Dock, только строка меню
        app.run()                             // блокирует, поэтому delegate жив всё время
    }
}
