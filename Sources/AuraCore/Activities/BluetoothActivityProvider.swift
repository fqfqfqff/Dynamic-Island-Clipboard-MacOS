import AppKit
import IOBluetooth
import SwiftUI

/// Наушники и прочие устройства Bluetooth: подключение, отключение и заряд.
///
/// Заряд AirPods система отдаёт только через `system_profiler`, а он думает
/// секунду-другую, поэтому запускается в фоне и только по событию подключения
/// либо раз в несколько минут.
/// Класс намеренно не изолирован целиком: IOBluetooth зовёт селекторы со
/// своего потока, и на изолированном классе это заканчивалось немедленным
/// падением приложения. Внутрь главного потока переходим сами.
final class BluetoothActivityProvider: NSObject {
    private let center: ActivityCenter
    private var connectionObserver: IOBluetoothUserNotification?
    private var refreshTimer: Timer?
    private var knownConnected: Set<String> = []
    private var batteries: [String: DeviceBatteryValues] = [:]
    private var isReadingBattery = false

    init(center: ActivityCenter) {
        self.center = center
        super.init()
    }

    @MainActor
    func start() {
        stop()

        // Первое обращение к Bluetooth поднимает системный запрос доступа,
        // а он блокирует поток до ответа пользователя. На главном потоке это
        // подвешивало всё приложение, поэтому спрашиваем в фоне и только
        // потом, уже с ответом, регистрируем наблюдателей.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let connected = paired.filter { $0.isConnected() }.compactMap(\.addressString)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.knownConnected = Set(connected)
                    self.registerObservers()
                    self.readBatteries()
                }
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readBatteries() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Уведомление о любом новом подключении. Отключение ловится отдельно,
    /// у каждого устройства своим наблюдателем.
    @MainActor
    private func registerObservers() {
        connectionObserver = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @MainActor
    func stop() {
        connectionObserver?.unregister()
        connectionObserver = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        knownConnected.removeAll()
    }

    // MARK: - События

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let address = device.addressString else { return }
                self.knownConnected.insert(address)

                device.register(
                    forDisconnectNotification: self,
                    selector: #selector(BluetoothActivityProvider.deviceDisconnected(_:device:))
                )

                self.present(device: device, connected: true)
                // Заряд появляется не сразу после соединения.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    MainActor.assumeIsolated { self?.readBatteries() }
                }
            }
        }
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let address = device.addressString else { return }
                self.knownConnected.remove(address)
                self.batteries[address] = nil
                self.present(device: device, connected: false)
            }
        }
    }

    @MainActor
    private func present(device: IOBluetoothDevice, connected: Bool) {
        let name = device.name ?? "Устройство"
        let battery = device.addressString.flatMap { batteries[$0]?.displayValue }

        center.upsert(
            Activity(
                id: "bluetooth.\(device.addressString ?? name)",
                title: name,
                subtitle: connected ? "Подключено" : "Отключено",
                symbol: Self.symbol(for: name, connected: connected),
                tint: connected ? .blue : .gray,
                priority: .normal,
                indicator: battery.map { Activity.Indicator.text("\($0)%") } ?? .none,
                expiresAt: Date().addingTimeInterval(connected ? 6 : 4)
            )
        )
    }

    // MARK: - Заряд

    @MainActor
    private func connectedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
    }

    @MainActor
    private func readBatteries() {
        guard !isReadingBattery, !connectedDevices().isEmpty else { return }
        isReadingBattery = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.parseBatteries(from: Self.runProfiler())
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isReadingBattery = false
                    for (name, battery) in parsed {
                        // Сопоставляем по имени: адрес profiler отдаёт рядом,
                        // но имя устройства читается человеком и стабильнее.
                        if let device = self.connectedDevices()
                            .first(where: { $0.name == name }),
                           let address = device.addressString {
                            self.batteries[address] = battery
                        }
                    }
                }
            }
        }
    }

    private static func runProfiler() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-detailLevel", "basic"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// Разбирает отступы вывода `system_profiler`: имя устройства — заголовок,
    /// уровни заряда — строки под ним.
    nonisolated static func parseBatteries(from output: String) -> [String: DeviceBatteryValues] {
        var result: [String: DeviceBatteryValues] = [:]
        var currentName: String?

        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasSuffix(":"), !line.contains("Battery"), !line.hasPrefix("Connected") {
                currentName = String(line.dropLast())
                continue
            }

            guard let name = currentName,
                  let percent = percentValue(from: line) else { continue }

            var values = result[name] ?? DeviceBatteryValues()
            if line.contains("Left") { values.left = percent }
            else if line.contains("Right") { values.right = percent }
            else if line.contains("Case") { values.caseLevel = percent }
            else if line.contains("Battery Level") { values.single = percent }
            result[name] = values
        }

        return result.filter { $0.value.displayValue != nil }
    }

    nonisolated private static func percentValue(from line: String) -> Int? {
        guard line.contains("Battery"), let range = line.range(of: ":") else { return nil }
        let tail = line[range.upperBound...]
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int(tail)
    }

    private static func symbol(for name: String, connected: Bool) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods") {
            return connected ? "airpods" : "airpods.gen3"
        }
        if lower.contains("mouse") || lower.contains("magic mouse") { return "magicmouse" }
        if lower.contains("keyboard") { return "keyboard" }
        if lower.contains("watch") { return "applewatch" }
        return connected ? "headphones" : "headphones.slash"
    }
}

/// Уровни заряда устройства. Вынесено наружу, чтобы разбор можно было
/// проверить тестами, не поднимая Bluetooth.
struct DeviceBatteryValues: Equatable {
    var left: Int?
    var right: Int?
    var single: Int?
    var caseLevel: Int?

    var displayValue: Int? {
        [left, right, single].compactMap { $0 }.min()
    }
}

