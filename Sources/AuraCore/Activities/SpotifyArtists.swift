import Foundation

/// Полный список исполнителей трека Spotify.
///
/// В словаре AppleScript у Spotify ровно одно текстовое поле `artist`, и для
/// трека с несколькими исполнителями оно отдаёт только первого. Списка там
/// нет вовсе — это ограничение самого Spotify, а не разбора ответа.
///
/// Взять остальных можно с публичной страницы трека: в `og:description` лежит
/// «Исполнитель1, Исполнитель2 · Альбом · Song · Год». Ни ключей, ни входа
/// это не требует — страница открыта всем.
///
/// Способ хрупкий по своей природе: разметку страницы Spotify может поменять
/// в любой день. Поэтому результат принимается только если он начинается
/// с того, что уже сказал AppleScript, — иначе остаётся прежнее имя.
/// Сломается разметка — станет как было, а не пусто.
enum SpotifyArtists {
    /// Запрошенное держим при себе: трек может повторяться, а страница
    /// у него не меняется.
    private nonisolated(unsafe) static var cache: [String: String] = [:]
    private nonisolated(unsafe) static let lock = NSLock()

    /// `spotify:track:0eGsy…` → `0eGsy…`
    static func trackID(from identifier: String) -> String? {
        let parts = identifier.split(separator: ":")
        guard parts.count == 3, parts[1] == "track", !parts[2].isEmpty else { return nil }
        return String(parts[2])
    }

    /// Строка исполнителей из `og:description`.
    ///
    /// Формат: «A, B · Альбом · Song · 2023». Нужна первая часть до точки
    /// с пробелами — остальное мы и так знаем.
    static func artists(fromDescription description: String) -> String? {
        let head = description.components(separatedBy: " · ").first?
            .trimmingCharacters(in: .whitespaces)
        guard let head, !head.isEmpty else { return nil }
        return head
    }

    /// Достаточно ли полученное похоже на правду, чтобы им заменить.
    static func isBetter(_ candidate: String, than known: String) -> Bool {
        guard candidate != known, !candidate.isEmpty else { return false }
        // Полный список начинается с первого исполнителя — того самого,
        // которого назвал AppleScript.
        return candidate.hasPrefix(known)
    }

    static func cached(_ id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[id]
    }

    /// Спрашивает страницу трека и отдаёт полный список исполнителей.
    static func lookup(id: String, known: String, completion: @escaping @Sendable (String) -> Void) {
        if let cached = cached(id) {
            completion(cached)
            return
        }
        guard let url = URL(string: "https://open.spotify.com/track/\(id)") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("Aura/0.2 (macOS notch player)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let html = String(data: data, encoding: .utf8),
                  let description = meta(named: "og:description", in: html),
                  let list = artists(fromDescription: description),
                  isBetter(list, than: known)
            else { return }

            lock.lock()
            cache[id] = list
            if cache.count > 200 { cache.removeAll() }
            lock.unlock()

            completion(list)
        }.resume()
    }

    /// Содержимое мета-тега. Разбирать HTML целиком незачем — нужен один тег.
    static func meta(named name: String, in html: String) -> String? {
        guard let range = html.range(of: "property=\"\(name)\"") else { return nil }
        let tail = html[range.upperBound...]
        guard let contentStart = tail.range(of: "content=\"") else { return nil }
        let value = tail[contentStart.upperBound...]
        guard let end = value.firstIndex(of: "\"") else { return nil }

        return String(value[..<end])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }
}
