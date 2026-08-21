import Foundation

/// Разбор ответа AppleScript от плеера. Вынесен отдельно от провайдера:
/// это единственная часть работы с музыкой, которую можно проверить тестами,
/// не поднимая ни Spotify, ни главный поток.
struct MusicResponse: Equatable {
    var title: String
    var artist: String?
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    var isPlaying: Bool
    var album: String?
    var artworkURL: String?

    /// Плееры отвечают числами в локали пользователя: в русской позиция
    /// приходит как «87,094», и обычный `Double(_:)` возвращает на этом nil —
    /// именно поэтому полоса длительности не появлялась.
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Плеер отвечает пятью строками и дальше — по возможностям: альбом,
    /// затем ссылка на обложку. Пустой заголовок означает, что играть нечего,
    /// — такой ответ не считается результатом.
    static func parse(_ text: String, durationDivisor: Double) -> MusicResponse? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 5 else { return nil }

        let title = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let album = lines.count >= 6 && !lines[5].isEmpty ? lines[5] : nil
        let artworkURL = lines.count >= 7 && !lines[6].isEmpty ? lines[6] : nil

        return MusicResponse(
            title: title,
            artist: lines[1].isEmpty ? nil : lines[1],
            duration: number(lines[2]).map { $0 / durationDivisor },
            elapsed: number(lines[3]),
            isPlaying: lines[4] == "true",
            album: album,
            artworkURL: artworkURL
        )
    }
}
