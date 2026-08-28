import AppKit
import AuraCore

/// Снимки интерфейса. Отдельный процесс, а не тест: видам нужен живой
/// `NSApplication` с рун-лупом, иначе AppKit не доводит слои до отрисовки.
///
/// Разрешения на запись экрана не требует — рисуются собственные виды, а не
/// то, что на экране.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let arguments = CommandLine.arguments
let directory = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/shots")

MainActor.assumeIsolated {
    let env = SnapshotScenes.probeEnvironment()
    print("экран: \(env.0)  вырез: \(env.1)  строкаМеню: \(env.2)  contentSize: \(env.3)")
}

// Отдельный режим: проверить поиск иконок приложений.
if arguments.count > 1, arguments[1] == "icons" {
    MainActor.assumeIsolated {
        let report = IconAudit.run()
        let broken = report.filter { !$0.found || $0.monogram }

        for item in broken {
            print("нет иконки: \(item.name)")
        }
        print("приложений: \(report.count), без своей иконки: \(broken.count)")
    }
    exit(0)
}

// Отдельный режим: нарисовать обложку приложения.
if arguments.count > 1, arguments[1] == "icon" {
    let target = arguments.count > 2
        ? URL(fileURLWithPath: arguments[2])
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/Aura.iconset")

    MainActor.assumeIsolated {
        if AppIconRenderer.writeIconset(to: target) != nil {
            print(target.path)
        } else {
            print("обложка не нарисовалась")
            exit(1)
        }
    }
    exit(0)
}

let written = MainActor.assumeIsolated { SnapshotRenderer.renderAll(into: directory) }
for url in written {
    print(url.path)
}
print("сцен: \(written.count)")
