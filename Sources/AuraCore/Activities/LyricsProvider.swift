import Foundation

/// Текст песни, синхронизированный по времени.
///
/// Берётся с lrclib.net — открытой базы, которая не требует ключей и отдаёт
/// строки с временными метками. Наружу уходят только название трека,
/// исполнитель и длительность; включается настройкой и по умолчанию выключено.
@MainActor
final class LyricsProvider: ObservableObject {
    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var isLoading = false

    private var currentKey: String?
    private var missing: Set<String> = []

    /// Строка, которая звучит сейчас, и следующая за ней.
    func lines(at time: TimeInterval) -> (current: String?, next: String?) {
        let triple = triple(at: time)
        return (triple.current, triple.next)
    }

    /// Прошедшая, текущая и следующая строки — тем, кто показывает текст
    /// колонкой и хочет, чтобы он читался как поток, а не как одна фраза.
    func triple(at time: TimeInterval) -> (previous: String?, current: String?, next: String?) {
        guard !lines.isEmpty else { return (nil, nil, nil) }

        guard let index = lines.lastIndex(where: { $0.time <= time + 0.2 }) else {
            // Вступление: текущей строки ещё нет, но следующую уже видно.
            return (nil, nil, lines.first?.text)
        }

        return (
            index > 0 ? lines[index - 1].text : nil,
            lines[index].text,
            index + 1 < lines.count ? lines[index + 1].text : nil
        )
    }

    func clear() {
        lines = []
        currentKey = nil
    }

    func load(title: String, artist: String?, duration: TimeInterval?) {
        let key = Self.key(title: title, artist: artist)
        guard key != currentKey else { return }
        currentKey = key
        lines = []

        guard !missing.contains(key) else { return }

        if let cached = Cache.read(key: key) {
            lines = cached
            return
        }

        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist ?? ""),
            URLQueryItem(name: "duration", value: duration.map { String(Int($0)) }),
        ].filter { $0.value?.isEmpty == false }

        guard let url = components?.url else { return }
        isLoading = true

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Сервис просит представляться — это в его правилах пользования.
        request.setValue("Aura/0.1 (macOS notch player)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let parsed = Self.parse(data)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.currentKey == key else { return }
                    self.isLoading = false

                    guard !parsed.isEmpty else {
                        // Запоминаем неудачу, чтобы не долбить сервис на каждый
                        // повтор одного и того же трека.
                        // Держим список коротким: за долгую сессию он иначе
                        // разрастается на каждый прослушанный трек.
                        if self.missing.count > 200 { self.missing.removeAll() }
                        self.missing.insert(key)
                        return
                    }
                    self.lines = parsed
                    Cache.write(parsed, key: key)
                }
            }
        }.resume()
    }

    // MARK: - Разбор

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private static func parse(_ data: Data?) -> [Line] {
        guard let data,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let synced = response.syncedLyrics, !synced.isEmpty
        else { return [] }

        return synced
            .components(separatedBy: .newlines)
            .compactMap(line(from:))
            .sorted { $0.time < $1.time }
    }

    /// Формат LRC: `[01:23.45] текст строки`.
    private static func line(from raw: String) -> Line? {
        guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { return nil }

        let stamp = raw[raw.index(after: raw.startIndex)..<close]
        let parts = stamp.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: "."))
        else { return nil }

        let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        return Line(time: minutes * 60 + seconds, text: text)
    }

    private static func key(title: String, artist: String?) -> String {
        "\(artist ?? "—") — \(title)".lowercased()
    }

    // MARK: - Кэш

    private enum Cache {
        static func url(for key: String) -> URL {
            let folder = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Aura/lyrics", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            // Имя файла из хеша: в названиях треков попадаются слэши и двоеточия.
            let name = String(format: "%08x", abs(key.hashValue))
            return folder.appendingPathComponent("\(name).json")
        }

        static func read(key: String) -> [Line]? {
            struct Stored: Codable {
                let time: TimeInterval
                let text: String
            }
            guard let data = try? Data(contentsOf: url(for: key)),
                  let stored = try? JSONDecoder().decode([Stored].self, from: data)
            else { return nil }
            return stored.map { Line(time: $0.time, text: $0.text) }
        }

        static func write(_ lines: [Line], key: String) {
            struct Stored: Codable {
                let time: TimeInterval
                let text: String
            }
            let stored = lines.map { Stored(time: $0.time, text: $0.text) }
            guard let data = try? JSONEncoder().encode(stored) else { return }
            try? data.write(to: url(for: key), options: .atomic)
        }
    }
}
