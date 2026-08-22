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
    /// у него не меняется. Кэш переживает перезапуск — иначе после каждого
    /// включения приложения второй исполнитель снова приезжал бы с задержкой.
    private nonisolated(unsafe) static var cache: [String: String] = loadCache()
    private nonisolated(unsafe) static let lock = NSLock()

    private static var cacheURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("spotify-artists.json")
    }

    private static func loadCache() -> [String: String] {
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored
    }

    private static func saveCache(_ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: cacheURL)
    }

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

        // Страница трека весит около четверти мегабайта, а нужный тег лежит
        // в первых двух килобайтах — он в `<head>`. Поэтому читаем поток
        // и обрываем соединение, как только тег найден: качать остальное
        // ради одной строки незачем, а на медленной сети это и есть та самая
        // задержка, с которой второй исполнитель появляется позже первого.
        let reader = HeadReader(marker: "og:description") { description in
            guard let list = artists(fromDescription: description),
                  isBetter(list, than: known) else { return }

            lock.lock()
            if cache.count > 300 { cache.removeAll() }
            cache[id] = list
            let snapshot = cache
            lock.unlock()
            saveCache(snapshot)

            completion(list)
        }
        reader.start(request)
    }
}

/// Читает начало ответа и обрывает загрузку, как только нашёл нужный тег.
///
/// Держит себя сам, пока не закончит: иначе делегат уходит из памяти раньше,
/// чем приходит первый байт.
private final class HeadReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let marker: String
    private let onFound: (String) -> Void
    private var buffer = Data()
    private var session: URLSession?
    private var retained: HeadReader?

    /// Больше этого не читаем: тега там нет, а страница длинная.
    private let limit = 32_768

    init(marker: String, onFound: @escaping (String) -> Void) {
        self.marker = marker
        self.onFound = onFound
    }

    func start(_ request: URLRequest) {
        retained = self
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        // Кусок может оборваться посреди символа — поэтому декодирование
        // с заменой, а не через `String(data:encoding:)`, который вернёт nil.
        let text = String(decoding: buffer, as: UTF8.self)
        if let value = SpotifyArtists.meta(named: marker, in: text) {
            finish(dataTask) { onFound(value) }
            return
        }
        if buffer.count > limit { finish(dataTask) {} }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        release()
    }

    private func finish(_ task: URLSessionDataTask, _ action: () -> Void) {
        task.cancel()
        action()
        release()
    }

    private func release() {
        session?.invalidateAndCancel()
        session = nil
        retained = nil
    }
}
