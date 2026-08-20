import Foundation
import Network

/// Локальный сокет, через который любое приложение или скрипт может показать
/// свою активность в вырезе.
///
/// Это и есть «интеграция с приложениями»: не Aura подстраивается под каждое
/// приложение, а даёт им одну простую точку входа.
@MainActor
final class ControlServer {
    static var socketURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        return base.appendingPathComponent("control.sock")
    }

    private var listener: NWListener?
    private let handle: (ControlCommand) -> String

    init(handle: @escaping (ControlCommand) -> String) {
        self.handle = handle
    }

    func start() {
        let url = Self.socketURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Сокет от прошлого запуска остаётся на диске и занимает путь.
        try? FileManager.default.removeItem(at: url)

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: url.path)
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                MainActor.assumeIsolated { self?.receive(on: connection) }
            }
            listener.start(queue: .main)
            self.listener = listener

            // Сокет позволяет рисовать что угодно в вырезе — доступ только
            // владельцу. Права выставляются после того, как сокет создан.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            }
            NSLog("Aura: управляющий сокет %@", url.path)
        } catch {
            NSLog("Aura: не удалось открыть сокет — %@", error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(at: Self.socketURL)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }

            if let data, !data.isEmpty {
                MainActor.assumeIsolated {
                    let response = self.respond(to: data)
                    connection.send(
                        content: response,
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                }
                return
            }

            if isComplete { connection.cancel() }
        }
    }

    private func respond(to data: Data) -> Data {
        let text: String
        do {
            text = handle(try ControlCommand.parse(json: data))
        } catch {
            text = #"{"ok":false,"error":"\#(error.localizedDescription)"}"#
        }
        return Data((text + "\n").utf8)
    }
}
