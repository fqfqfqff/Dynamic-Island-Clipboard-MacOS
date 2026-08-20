import AppKit

/// Проверка новой версии на GitHub.
///
/// Обновление не скачивается и не ставится само: приложение собирается из
/// исходников, и подменять бинарь на ходу было бы и сложнее, и наглее.
/// Задача — сообщить, что версия устарела, и дать ссылку.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var available: Release?

    /// Заполняется при сборке своего форка; пока не задан — проверка молчит.
    private let repository = "kekch/aura"
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        stop()
        check()

        // Раз в сутки: чаще нет смысла, а дёргать чужой сервис почём зря — дурной тон.
        let timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let link = json["html_url"] as? String,
                  let releaseURL = URL(string: link)
            else { return }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                    guard Self.isNewer(latest, than: self.currentVersion) else {
                        self.available = nil
                        return
                    }
                    self.available = Release(version: latest, url: releaseURL)
                }
            }
        }.resume()
    }

    /// Сравнение версий по числам: «0.10.0» новее «0.9.0», хотя строкой — наоборот.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
